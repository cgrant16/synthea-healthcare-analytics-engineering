# =============================================================================
# 02_setup_iam_for_snowflake.ps1  -  Least-privilege IAM role for Snowflake
# Author: Cortwright Grant
#
# This runs TWICE, in two phases (the two halves of the Snowflake handshake):
#
#  Phase A (before Snowflake):  creates the read-only policy and the role, with a
#     placeholder trust policy that trusts nobody but your own account.
#       powershell -ExecutionPolicy Bypass -File .\02_setup_iam_for_snowflake.ps1
#
#  Phase B (after `DESC INTEGRATION SYNTHEA_S3_INT` in Snowflake): locks the
#     trust policy to Snowflake's IAM user + external ID.
#       powershell -ExecutionPolicy Bypass -File .\02_setup_iam_for_snowflake.ps1 `
#           -SnowflakeIamUserArn 'arn:aws:iam::123456789012:user/abc1-s-xxxx1234' `
#           -SnowflakeExternalId 'ABC12345_SFCRole=2_xxxxxxxxxxxxxxxxxxxxxxx='
# =============================================================================
param(
    [string]$SnowflakeIamUserArn,   # STORAGE_AWS_IAM_USER_ARN from DESC INTEGRATION
    [string]$SnowflakeExternalId    # STORAGE_AWS_EXTERNAL_ID  from DESC INTEGRATION
)

. "$PSScriptRoot\00_config.ps1"

$AccountId = (aws sts get-caller-identity --query Account --output text)
Assert-LastExit 'sts get-caller-identity'

$PolicyArn = "arn:aws:iam::${AccountId}:policy/$IamPolicyName"
$RoleArn   = "arn:aws:iam::${AccountId}:role/$IamRoleName"

$TemplateDir = Join-Path $PSScriptRoot 'iam'
$RenderDir   = Join-Path $TemplateDir 'rendered'      # gitignored
New-Item -ItemType Directory -Force -Path $RenderDir | Out-Null

# Fill <PLACEHOLDERS> in a template and write UTF-8 *without* BOM (the AWS CLI
# rejects a BOM, which Windows PowerShell 5.1's Set-Content -Encoding UTF8 adds).
function Render-Template([string]$TemplateName, [string]$OutName, [hashtable]$Values) {
    $text = Get-Content (Join-Path $TemplateDir $TemplateName) -Raw
    foreach ($k in $Values.Keys) { $text = $text.Replace($k, $Values[$k]) }
    $out = Join-Path $RenderDir $OutName
    [System.IO.File]::WriteAllText($out, $text)
    return $out
}

# =============================================================================
# PHASE B - finalize trust once Snowflake has told us who it is
# =============================================================================
if ($SnowflakeIamUserArn -or $SnowflakeExternalId) {
    if (-not ($SnowflakeIamUserArn -and $SnowflakeExternalId)) {
        throw 'Phase B needs BOTH -SnowflakeIamUserArn and -SnowflakeExternalId.'
    }
    Write-Host "`n== PHASE B: lock trust policy to Snowflake ==" -ForegroundColor Cyan

    $trust = Render-Template 'snowflake-trust-policy.template.json' 'trust-policy-final.json' @{
        '<TRUSTED_PRINCIPAL_ARN>' = $SnowflakeIamUserArn
        '<EXTERNAL_ID>'           = $SnowflakeExternalId
    }
    aws iam update-assume-role-policy --role-name $IamRoleName --policy-document "file://$trust"
    Assert-LastExit 'update-assume-role-policy'

    aws iam get-role --role-name $IamRoleName --query 'Role.AssumeRolePolicyDocument' --output json
    Write-Host "`nDone. IAM changes can take ~1 minute to propagate before LIST @stage works."
    return
}

# =============================================================================
# PHASE A - policy + role with placeholder trust
# =============================================================================
Write-Host "`n== PHASE A: least-privilege policy ==" -ForegroundColor Cyan

$policy = Render-Template 'snowflake-s3-read-policy.template.json' 'snowflake-s3-read-policy.json' @{
    '<BUCKET>' = $Bucket
    '<PREFIX>' = $Prefix
}

aws iam get-policy --policy-arn $PolicyArn *> $null
if ($LASTEXITCODE -eq 0) {
    # Policy exists: publish the current template as the new default version.
    # (IAM keeps max 5 versions; delete old ones with `aws iam delete-policy-version` if this fails.)
    aws iam create-policy-version --policy-arn $PolicyArn --policy-document "file://$policy" --set-as-default
    Assert-LastExit 'create-policy-version'
} else {
    aws iam create-policy --policy-name $IamPolicyName --policy-document "file://$policy" `
        --description "Snowflake read-only access to s3://$Bucket/$Prefix/ (Synthea)"
    Assert-LastExit 'create-policy'
}

Write-Host "`n== PHASE A: role (placeholder trust) ==" -ForegroundColor Cyan

aws iam get-role --role-name $IamRoleName *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Role $IamRoleName already exists - leaving its trust policy untouched."
} else {
    # Placeholder: trusts only YOUR account with a dummy external ID, so nobody
    # (including Snowflake) can assume it until Phase B replaces this.
    $bootstrap = Render-Template 'snowflake-trust-policy.template.json' 'trust-policy-bootstrap.json' @{
        '<TRUSTED_PRINCIPAL_ARN>' = "arn:aws:iam::${AccountId}:root"
        '<EXTERNAL_ID>'           = '0000'
    }
    aws iam create-role --role-name $IamRoleName --assume-role-policy-document "file://$bootstrap" `
        --description 'Assumed by the Snowflake storage integration SYNTHEA_S3_INT (read-only)' `
        --tags 'Key=project,Value=synthea-analytics'
    Assert-LastExit 'create-role'
}

aws iam attach-role-policy --role-name $IamRoleName --policy-arn $PolicyArn
Assert-LastExit 'attach-role-policy'

Write-Host "`n------------------------------------------------------------------"
Write-Host "Role ARN for CREATE STORAGE INTEGRATION (STORAGE_AWS_ROLE_ARN):"
Write-Host "  $RoleArn" -ForegroundColor Green
Write-Host "Allowed location (STORAGE_ALLOWED_LOCATIONS):"
Write-Host "  s3://$Bucket/$Prefix/" -ForegroundColor Green
Write-Host "------------------------------------------------------------------"
