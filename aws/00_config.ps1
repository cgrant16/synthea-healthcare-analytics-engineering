# =============================================================================
# 00_config.ps1  -  Shared settings for the AWS-side scripts (Windows PowerShell)
# Author: Cortwright Grant
#
# Edit the values below ONCE. 01_* and 02_* dot-source this file, so every
# script uses the same bucket, prefix, profile and IAM names.
# =============================================================================

# Named CLI profile, so this project's keys never collide with anything else.
$AwsProfile = 'synthea'

# MUST match your Snowflake account's region (avoids cross-region egress cost).
# In Snowflake run:  SELECT CURRENT_REGION();   e.g. AWS_US_EAST_1 -> us-east-1
$Region = 'us-east-2'

# Globally unique, lowercase, 3-63 chars, no dots. Pick once, never change.
# Idea: '<your-initials>-synthea-landing-<6 random digits>'
#   (generate the digits once with:  Get-Random -Minimum 100000 -Maximum 999999)
$Bucket = 'CHANGE-ME-synthea-landing'

# Landing prefix. One sub-folder per source table is created under it:
#   s3://<bucket>/synthea-v2/csv/patients/...
#   s3://<bucket>/synthea-v2/csv/encounters/...
$Prefix = 'synthea-v2/csv'

# Where the downloaded SyntheticMass archive lives, and where CSVs get extracted.
$ArchivePath = 'C:\Users\CHANGE-ME\Downloads\synthea_sample_data_csv.tar.gz'
$ExtractDir  = 'C:\synthea\extract'

# IAM objects that Snowflake's storage integration will use.
$IamRoleName   = 'synthea-snowflake-s3-read-role'
$IamPolicyName = 'synthea-snowflake-s3-read-policy'

# -----------------------------------------------------------------------------
# Session plumbing (no edits needed below)
# -----------------------------------------------------------------------------
$env:AWS_PROFILE        = $AwsProfile
$env:AWS_DEFAULT_REGION = $Region

function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI step failed: $Step (exit code $LASTEXITCODE)" }
}

if ($Bucket -like '*CHANGE-ME*' -or $ArchivePath -like '*CHANGE-ME*') {
    throw 'Edit aws\00_config.ps1 first: set $Bucket and $ArchivePath.'
}
