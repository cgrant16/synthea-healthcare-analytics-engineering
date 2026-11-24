#!/usr/bin/env bash
# =============================================================================
# mac_add_prefix_to_iam_policy.sh  -  Let Snowflake read one more S3 prefix.
# Author: Cortwright Grant
#
# The read-only policy on synthea-snowflake-s3-read-role allows GetObject and
# ListBucket under synthea-v2/csv/ only. The current-version dataset lands under
# synthea-2026/csv/, so that prefix must be added - and nothing else.
#
# It reads the policy's live default version, ADDS the new prefix to the two
# statements that name a prefix, and publishes the result as a new version.
# Existing prefixes are kept, the role's trust policy is not touched, and the
# policy stays read-only.
#
# Usage:  BUCKET=<bucket> ./mac_add_prefix_to_iam_policy.sh            # dry run: show the change
#         BUCKET=<bucket> APPLY=1 ./mac_add_prefix_to_iam_policy.sh    # publish the new version
# Re-runnable: if the prefix is already allowed it changes nothing.
#
# AFTER this, widen the Snowflake side too:
#   snowflake/05_raw_2026_landing.sql, section C (STORAGE_ALLOWED_LOCATIONS).
# =============================================================================
set -euo pipefail

BUCKET="${BUCKET:?Set BUCKET=<your-bucket-name>}"
NEW_PREFIX="${NEW_PREFIX:-synthea-2026/csv}"
POLICY_NAME="${POLICY_NAME:-synthea-snowflake-s3-read-policy}"
APPLY="${APPLY:-0}"

HERE="$(cd "$(dirname "$0")" && pwd)"
RENDERED="$HERE/iam/rendered"            # gitignored: holds account-specific JSON
mkdir -p "$RENDERED"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ARN="arn:aws:iam::${ACCOUNT}:policy/${POLICY_NAME}"
VERSION=$(aws iam get-policy --policy-arn "$ARN" --query 'Policy.DefaultVersionId' --output text)

aws iam get-policy-version --policy-arn "$ARN" --version-id "$VERSION" \
    --query 'PolicyVersion.Document' --output json > "$RENDERED/policy-current.json"

# Add the prefix to (a) the object statement's Resource and (b) the ListBucket
# statement's s3:prefix condition. Exit 3 = already allowed, nothing to do.
set +e
python3 - "$BUCKET" "$NEW_PREFIX" "$RENDERED/policy-current.json" "$RENDERED/policy-new.json" <<'PY'
import json, sys
bucket, prefix, src, dst = sys.argv[1:5]
prefix = prefix.strip('/')
doc = json.load(open(src))
changed = False

def as_list(value):
    return value if isinstance(value, list) else [value]

for st in as_list(doc['Statement']):
    actions = as_list(st.get('Action', []))
    if any(a in ('s3:GetObject', 's3:GetObjectVersion') for a in actions):
        resources = as_list(st['Resource'])
        want = f'arn:aws:s3:::{bucket}/{prefix}/*'
        if want not in resources:
            resources.append(want); changed = True
        st['Resource'] = resources
    if 's3:ListBucket' in actions:
        cond = st.get('Condition', {}).get('StringLike', {})
        if 's3:prefix' not in cond:
            sys.exit('ListBucket statement has no s3:prefix condition - edit the policy by hand.')
        prefixes = as_list(cond['s3:prefix'])
        for want in (f'{prefix}/', f'{prefix}/*'):
            if want not in prefixes:
                prefixes.append(want); changed = True
        cond['s3:prefix'] = prefixes

# Same formatting as `python3 -m json.tool`, so the diff below shows only real changes.
with open(dst, 'w') as out:
    json.dump(doc, out, indent=4)
    out.write('\n')
sys.exit(0 if changed else 3)
PY
rc=$?
set -e

if [ "$rc" = "3" ]; then
  echo "Policy $POLICY_NAME ($VERSION) already allows $NEW_PREFIX/ - nothing to do."
  exit 0
elif [ "$rc" != "0" ]; then
  exit "$rc"
fi

echo "Policy:  $POLICY_NAME   current default version: $VERSION"
echo "Change (current -> new):"
diff <(python3 -m json.tool "$RENDERED/policy-current.json") "$RENDERED/policy-new.json" | sed 's/^/  /' || true

if [ "$APPLY" != "1" ]; then
  echo
  echo "Dry run - nothing changed. Re-run with APPLY=1 to publish this as the new default version."
  exit 0
fi

# IAM keeps at most 5 versions per policy.
COUNT=$(aws iam list-policy-versions --policy-arn "$ARN" --query 'length(Versions)' --output text)
if [ "$COUNT" -ge 5 ]; then
  echo "Policy already has 5 versions. Delete an old non-default one first:"
  echo "  aws iam list-policy-versions --policy-arn $ARN"
  echo "  aws iam delete-policy-version --policy-arn $ARN --version-id <vN>"
  exit 1
fi

aws iam create-policy-version --policy-arn "$ARN" \
    --policy-document "file://$RENDERED/policy-new.json" --set-as-default \
    --query 'PolicyVersion.VersionId' --output text | sed 's/^/Published new default version: /'
echo "IAM changes can take about a minute to take effect."
