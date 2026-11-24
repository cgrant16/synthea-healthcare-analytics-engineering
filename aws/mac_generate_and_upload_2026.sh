#!/usr/bin/env bash
# =============================================================================
# mac_generate_and_upload_2026.sh  -  Generate a current-version Synthea
#                                     population and land its CSVs in S3.
# Author: Cortwright Grant
#
# Why a second dataset: the SyntheticMass v2 (2017) extract has no providers,
# organizations, payers, claims or costs in any of its formats (CSV, FHIR,
# C-CDA). Current Synthea exports all of them: 18 CSV tables instead of 9.
#
# Needs:
#   * Java 17 or 25 (LTS):   brew install openjdk@17
#   * synthea-with-dependencies.jar from
#     https://github.com/synthetichealth/synthea/releases
#     Use the "master-branch-latest" build. The tagged v4.0.0 release does NOT
#     write the NPI column on organizations.csv / providers.csv.
#     This project used the build published 2026-11-20 (commit 5441eef):
#       sha256 1584dd9d4f8a393d64c6a5bcc8058bf075c38b2ae34676daf3b60977a092eddb
#
# What it does:
#   1. Generate POPULATION living patients (those who die along the way are
#      exported too), full history, CSV only. Skipped if output already exists.
#   2. gzip every CSV part into one folder per table.
#   3. Print an inventory: files, data lines and compressed size per table.
#   4. Upload to s3://<bucket>/synthea-2026/csv/<table>/<table>__part_NNN.csv.gz
#   5. Print the S3 summary.
#
# Usage:  ./mac_generate_and_upload_2026.sh                              # generate + gzip + inventory only
#         BUCKET=<bucket> ./mac_generate_and_upload_2026.sh              # ...plus an upload dry run
#         BUCKET=<bucket> UPLOAD=1 ./mac_generate_and_upload_2026.sh     # ...and actually upload
# Re-runnable: every step skips work already done.
# =============================================================================
set -euo pipefail

JAVA="${JAVA:-/opt/homebrew/opt/openjdk@17/bin/java}"
JAR="${JAR:-$HOME/synthea_work/synthea_latest_generator/synthea-with-dependencies.jar}"
WORK="${WORK:-$HOME/synthea_work/synthea_latest_10k}"   # keep OUT of Google Drive / iCloud folders
POPULATION="${POPULATION:-10000}"
SEED="${SEED:-20261123}"            # same seed + reference date + build = same patients
REFDATE="${REFDATE:-20261123}"      # "today" for the simulation, as YYYYMMDD
STATE="${STATE:-Massachusetts}"     # same state as the 2017 extract
MAX_LINES="${MAX_LINES:-1000000}"   # split big tables so Snowflake can load parts in parallel
PREFIX="${PREFIX:-synthea-2026/csv}"
BUCKET="${BUCKET:-}"
UPLOAD="${UPLOAD:-0}"
JOBS="${JOBS:-6}"                   # parallel gzip jobs

OUT="$WORK/out"; GZ="$WORK/gz"
mkdir -p "$WORK/run" "$GZ"
log() { printf '%s  %s\n' "$(date +%T)" "$*"; }

# --- 1. Generate --------------------------------------------------------------
if ls "$OUT"/csv/patients-*.csv >/dev/null 2>&1; then
  log "Synthea output already present in $OUT/csv - skipping generation."
else
  log "Generating $POPULATION patients ($STATE, seed $SEED) ..."
  # Synthea writes relative paths from the current directory, so run it from an
  # empty folder of its own. exporter.years_of_history=0 keeps the full record;
  # the default of 10 would drop everything older than ten years.
  ( cd "$WORK/run" && "$JAVA" -Xmx10g -jar "$JAR" \
      -p "$POPULATION" -s "$SEED" -cs "$SEED" -r "$REFDATE" \
      --exporter.csv.export=true \
      --exporter.fhir.export=false \
      --exporter.hospital.fhir.export=false \
      --exporter.practitioner.fhir.export=false \
      --exporter.years_of_history=0 \
      --exporter.csv.max_lines_per_file="$MAX_LINES" \
      --exporter.baseDirectory="$OUT/" \
      "$STATE" ) > "$WORK/run.log" 2>&1
  grep -a "Records: total" "$WORK/run.log" || { echo "Generation failed - see $WORK/run.log"; exit 1; }
fi

# --- 2. gzip each part into <table>/<table>__part_NNN.csv.gz ---------------------
# Synthea names parts <table>-<N>.csv; N is zero-padded here so S3 lists in order.
gzip_part() {
  local src="$1" gzroot="$2"
  local base; base=$(basename "$src" .csv)
  local table="${base%-*}" n="${base##*-}"
  local dst; dst=$(printf '%s/%s/%s__part_%03d.csv.gz' "$gzroot" "$table" "$table" "$n")
  if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then return; fi
  mkdir -p "$(dirname "$dst")"
  gzip -c -6 "$src" > "$dst.tmp" && mv "$dst.tmp" "$dst"
}
export -f gzip_part
log "Compressing CSV parts ($JOBS in parallel) ..."
ls "$OUT"/csv/*.csv | xargs -P "$JOBS" -I{} bash -c 'gzip_part "$1" "$2"' _ {} "$GZ"

# --- 3. Inventory ----------------------------------------------------------------
# "data lines" = lines minus one header per part. Compare with the row counts in
# snowflake/06_raw_2026_verification.sql after loading.
log "Inventory (table, parts, data lines, compressed MB):"
for dir in "$GZ"/*/; do
  table=$(basename "$dir")
  parts=$(ls "$dir"/*.csv.gz | wc -l | tr -d ' ')
  lines=$(cat "$OUT"/csv/"$table"-*.csv | wc -l | tr -d ' ')
  mb=$(du -cm "$dir"/*.csv.gz | tail -1 | cut -f1)
  printf '  %-20s %3s parts  %11s lines  %6s MB\n' "$table" "$parts" "$((lines - parts))" "$mb"
done

# --- 4. Upload -------------------------------------------------------------------
if [ -z "$BUCKET" ]; then
  log "BUCKET not set - stopping before the upload step."
  exit 0
fi
if [ "$UPLOAD" = "1" ]; then
  log "Uploading to s3://$BUCKET/$PREFIX/ ..."
  aws s3 sync "$GZ/" "s3://$BUCKET/$PREFIX/" --exclude '*' --include '*.csv.gz' --only-show-errors
else
  log "Dry run - nothing is uploaded. Planned keys:"
  aws s3 sync "$GZ/" "s3://$BUCKET/$PREFIX/" --exclude '*' --include '*.csv.gz' --dryrun | sed 's/^/  /'
fi

# --- 5. Verify -------------------------------------------------------------------
if [ "$UPLOAD" = "1" ]; then
  log "S3 summary:"
  aws s3 ls "s3://$BUCKET/$PREFIX/" --recursive --human-readable --summarize | tail -3
fi
log "Finished."
