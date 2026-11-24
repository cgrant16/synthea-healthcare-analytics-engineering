# =============================================================================
# 01_setup_s3_and_upload.ps1  -  Credentials, bucket, CSV extract, upload
# Author: Cortwright Grant
#
# Run from PowerShell on the Windows machine, inside the aws\ folder:
#
#   powershell -ExecutionPolicy Bypass -File .\01_setup_s3_and_upload.ps1           # dry run
#   powershell -ExecutionPolicy Bypass -File .\01_setup_s3_and_upload.ps1 -Upload   # real upload
#
# Every step is idempotent: re-running skips work that is already done.
# =============================================================================
param(
    [switch]$Upload   # without this switch, step 5 only PRINTS what it would upload
)

. "$PSScriptRoot\00_config.ps1"

# -----------------------------------------------------------------------------
# STEP 1 - Configure credentials (named profile)
#
# Use an IAM *user* access key (or IAM Identity Center / `aws configure sso`),
# never root-account keys. For a personal project an admin IAM user is fine;
# Snowflake itself will NOT use these keys - it gets its own read-only role.
# -----------------------------------------------------------------------------
Write-Host "`n== STEP 1: credentials (profile '$AwsProfile') ==" -ForegroundColor Cyan

$existingKey = aws configure get aws_access_key_id --profile $AwsProfile 2>$null
if (-not $existingKey) {
    # Interactive: prompts for Access Key ID, Secret Access Key, region, output.
    aws configure --profile $AwsProfile
    Assert-LastExit 'aws configure'
}
aws configure set region $Region --profile $AwsProfile
aws configure set output json   --profile $AwsProfile

# Proves the keys work and shows WHICH identity you are (should not be root).
aws sts get-caller-identity
Assert-LastExit 'sts get-caller-identity (credentials are not working)'

# -----------------------------------------------------------------------------
# STEP 2 - Create and harden the bucket
# -----------------------------------------------------------------------------
Write-Host "`n== STEP 2: bucket s3://$Bucket ==" -ForegroundColor Cyan

aws s3api head-bucket --bucket $Bucket *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Bucket already exists and is yours - skipping create."
} else {
    if ($Region -eq 'us-east-1') {
        # us-east-1 is the one region that must NOT pass a LocationConstraint.
        aws s3api create-bucket --bucket $Bucket --region $Region
    } else {
        aws s3api create-bucket --bucket $Bucket --region $Region `
            --create-bucket-configuration LocationConstraint=$Region
    }
    Assert-LastExit 'create-bucket'
}

# Block ALL public access (AWS default for new buckets; set explicitly so it's documented).
aws s3api put-public-access-block --bucket $Bucket `
    --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
Assert-LastExit 'put-public-access-block'

# Disable ACLs entirely - access is governed only by IAM policies.
aws s3api put-bucket-ownership-controls --bucket $Bucket `
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
Assert-LastExit 'put-bucket-ownership-controls'

# Default encryption at rest (SSE-S3). Shorthand syntax avoids PowerShell JSON-quoting bugs.
aws s3api put-bucket-encryption --bucket $Bucket `
    --server-side-encryption-configuration 'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]'
Assert-LastExit 'put-bucket-encryption'

aws s3api put-bucket-tagging --bucket $Bucket `
    --tagging 'TagSet=[{Key=project,Value=synthea-analytics},{Key=purpose,Value=landing-zone}]'
Assert-LastExit 'put-bucket-tagging'

# -----------------------------------------------------------------------------
# STEP 3 - Extract ONLY the CSV files from the archive
#
# Windows 10+ ships bsdtar as `tar.exe`; it reads .tar.gz, .tgz AND .zip.
# --include '*.csv' skips the FHIR / C-CDA payload entirely.
# Note: a 21 GB gzip must be decompressed end-to-end, so this takes a while.
# -----------------------------------------------------------------------------
Write-Host "`n== STEP 3: extract CSVs to $ExtractDir ==" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
$alreadyExtracted = Get-ChildItem -Path $ExtractDir -Recurse -File -Filter '*.csv' -ErrorAction SilentlyContinue |
                    Select-Object -First 1
if ($alreadyExtracted) {
    Write-Host "CSV files already present in $ExtractDir - skipping extraction."
} else {
    if (-not (Test-Path $ArchivePath)) { throw "Archive not found: $ArchivePath" }
    # Optional peek first (also slow on a big .gz):
    #   tar -tf $ArchivePath | Select-String '\.csv$' | Select-Object -First 50
    tar -xf $ArchivePath -C $ExtractDir --include '*.csv'
    if ($LASTEXITCODE -ne 0) { throw 'tar extraction failed' }
}

# -----------------------------------------------------------------------------
# STEP 4 - Inventory: what tables / files / sizes did we get?
#
# Table name = file name, lower-cased, with any numeric chunk suffix removed
# (patients.csv, patients_2.csv -> 'patients'). REVIEW THIS TABLE before uploading.
# -----------------------------------------------------------------------------
Write-Host "`n== STEP 4: inventory ==" -ForegroundColor Cyan

function Get-TableName([System.IO.FileInfo]$File) {
    return ($File.BaseName.ToLower() -replace '[_-]?\d+$', '')
}

$csvFiles = Get-ChildItem -Path $ExtractDir -Recurse -File -Filter '*.csv'
if (-not $csvFiles) { throw "No CSV files found under $ExtractDir" }

$csvFiles |
    Group-Object { Get-TableName $_ } |
    ForEach-Object {
        [pscustomobject]@{
            Table  = $_.Name
            Files  = $_.Count
            SizeGB = [math]::Round((($_.Group | Measure-Object Length -Sum).Sum / 1GB), 2)
        }
    } |
    Sort-Object Table | Format-Table -AutoSize

# -----------------------------------------------------------------------------
# STEP 5 - Upload into one prefix per table
#
#   s3://<bucket>/synthea-v2/csv/<table>/<sub-folder-tag>__<file>.csv
#
# Per-table prefixes let Snowflake COPY/INFER_SCHEMA target exactly one table's
# files. The sub-folder tag keeps names unique if the archive has several
# chunks that each contain their own patients.csv.
# `aws s3 cp` handles multipart upload of large files automatically.
# -----------------------------------------------------------------------------
Write-Host "`n== STEP 5: upload ($(if ($Upload) {'LIVE'} else {'DRY RUN - add -Upload to execute'})) ==" -ForegroundColor Cyan

$root = (Resolve-Path $ExtractDir).Path.TrimEnd('\')
foreach ($f in $csvFiles) {
    $table  = Get-TableName $f
    $relDir = $f.DirectoryName.Substring($root.Length).Trim('\')
    $tag    = if ($relDir) { (($relDir -replace '[\\/\s]+', '_').ToLower()) + '__' } else { '' }
    $key    = "$Prefix/$table/$tag$($f.Name.ToLower())"

    if ($Upload) {
        Write-Host "  -> s3://$Bucket/$key"
        aws s3 cp $f.FullName "s3://$Bucket/$key" --only-show-errors
        Assert-LastExit "upload $($f.FullName)"
    } else {
        Write-Host "  [dry run] $($f.FullName)  ->  s3://$Bucket/$key"
    }
}

# -----------------------------------------------------------------------------
# STEP 6 - Verify what landed
# -----------------------------------------------------------------------------
if ($Upload) {
    Write-Host "`n== STEP 6: verify ==" -ForegroundColor Cyan
    aws s3 ls "s3://$Bucket/$Prefix/" --recursive --human-readable --summarize
}
