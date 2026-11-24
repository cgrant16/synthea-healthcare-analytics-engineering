#!/usr/bin/env bash
# =============================================================================
# mac_extract_and_upload.sh  -  macOS equivalent of 01_setup_s3_and_upload.ps1
#                               (steps 3-6), for the nested SyntheticMass archive.
# Author: Cortwright Grant
#
# Archive layout (SyntheticMass v2, 24 May 2017):
#   synthea_1m_fhir_3_0_May_24.tar.gz            22 GB
#     └─ output_<N>_<timestamp>.tar.gz  x 12     ~1.9 GB each, one per batch
#          └─ output_<N>/{fhir,CCDA,csv,...}
#               └─ csv/<table>.csv  x 9          ~1.3 GB per batch
#
# What it does:
#   1. Unpack the 12 batch archives once (outer gzip is read a single time).
#   2. From each batch extract ONLY output_<N>/csv/*.csv (FHIR/C-CDA skipped).
#   3. gzip each CSV (~5x smaller upload; Snowflake auto-detects .gz).
#   4. Upload to s3://<bucket>/synthea-v2/csv/<table>/batch_<NN>__<table>.csv.gz
#   5. Print the S3 inventory.
#
# Usage:  BUCKET=<bucket> ./mac_extract_and_upload.sh            # extract + compress, then dry run
#         BUCKET=<bucket> UPLOAD=1 ./mac_extract_and_upload.sh   # ...and actually upload
# Re-runnable: every step skips work already done.
# =============================================================================
set -euo pipefail

ARCHIVE="${ARCHIVE:-$HOME/Downloads/synthea_1m_fhir_3_0_May_24.tar.gz}"
WORK="${WORK:-$HOME/synthea_work}"          # keep OUT of Google Drive / iCloud folders
BUCKET="${BUCKET:?Set BUCKET=<your-bucket-name> (e.g. BUCKET=xx-synthea-landing-123456 ./mac_extract_and_upload.sh)}"
PREFIX="${PREFIX:-synthea-v2/csv}"
UPLOAD="${UPLOAD:-0}"
JOBS="${JOBS:-4}"                            # parallel batch extractions

BATCHES="$WORK/batches"; CSV="$WORK/csv"
mkdir -p "$BATCHES" "$CSV"
log() { printf '%s  %s\n' "$(date +%T)" "$*"; }

# --- 1. Unpack the 12 inner batch archives -----------------------------------
if [ "$(ls "$BATCHES"/*.tar.gz 2>/dev/null | wc -l)" -lt 12 ]; then
  log "Unpacking batch archives from $(basename "$ARCHIVE") ..."
  tar -xzf "$ARCHIVE" -C "$BATCHES" --strip-components 1
fi
log "Batch archives: $(ls "$BATCHES"/*.tar.gz | wc -l | tr -d ' ')"

# --- 2+3. Extract CSVs per batch and gzip them --------------------------------
extract_batch() {
  local tgz="$1" csvroot="$2"
  local n; n=$(basename "$tgz" | sed -E 's/^output_([0-9]+)_.*/\1/')
  local nn; nn=$(printf '%02d' "$n")
  local out="$csvroot/batch_$nn"
  if [ -f "$out/.done" ]; then echo "batch $nn already done"; return; fi
  mkdir -p "$out"
  tar -xzf "$tgz" -C "$out" --strip-components 2 --include "output_$n/csv/*.csv"
  for f in "$out"/*.csv; do gzip -f -6 "$f"; done
  touch "$out/.done"; echo "batch $nn done: $(ls "$out"/*.csv.gz | wc -l | tr -d ' ') files"
}
export -f extract_batch
log "Extracting CSVs ($JOBS batches in parallel) ..."
ls "$BATCHES"/*.tar.gz | xargs -P "$JOBS" -I{} bash -c 'extract_batch "$1" "$2"' _ {} "$CSV"

# --- Inventory ----------------------------------------------------------------
log "Inventory (table, files, compressed MB):"
for t in $(ls "$CSV"/batch_*/ | grep '\.csv\.gz$' | sed 's/\.csv\.gz$//' | sort -u); do
  files=$(ls "$CSV"/batch_*/"$t".csv.gz | wc -l | tr -d ' ')
  mb=$(du -cm "$CSV"/batch_*/"$t".csv.gz | tail -1 | cut -f1)
  printf '  %-15s %3s files  %6s MB\n' "$t" "$files" "$mb"
done

# --- 4. Upload ------------------------------------------------------------------
for f in "$CSV"/batch_*/*.csv.gz; do
  batch=$(basename "$(dirname "$f")"); table=$(basename "$f" .csv.gz)
  key="$PREFIX/$table/${batch}__${table}.csv.gz"
  if [ "$UPLOAD" = "1" ]; then
    aws s3 cp "$f" "s3://$BUCKET/$key" --only-show-errors && echo "  uploaded $key"
  else
    echo "  [dry run] $f -> s3://$BUCKET/$key"
  fi
done

# --- 5. Verify --------------------------------------------------------------------
if [ "$UPLOAD" = "1" ]; then
  log "S3 inventory:"
  aws s3 ls "s3://$BUCKET/$PREFIX/" --recursive --human-readable --summarize | tail -3
fi
log "Finished."
