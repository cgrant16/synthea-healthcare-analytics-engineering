#!/usr/bin/env python3
"""
quarantine_patients.py - split the SyntheticMass v2 patients CSVs into
clean rows and rejected rows *before* they are loaded into Snowflake RAW.

Author: Cortwright Grant

Why this exists
---------------
The 2017 SyntheticMass patients.csv files contain lines where records were
spliced together during generation (e.g. a 33-field line = two patients
interleaved), plus the orphaned fragments those splices leave behind.
Across all 12 batches: 1,590,897 well-formed rows, 4,153 malformed lines
(0.26%). 3,694 patients (0.23%) appear only inside those lines and
have no clean row; their encounters etc. become orphans in RAW.
The 8 other tables have zero malformed rows.

Snowflake cannot quarantine these reliably:
  * MATCH_BY_COLUMN_NAME requires ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    (the audit columns count as extra fields), so bad rows load silently.
  * Positional COPY ... FROM (SELECT $1..$17 ...) ignores the column-count
    check entirely (tested: 289 garbage rows loaded from batch_01).

Rule
----
A line is CLEAN if it has exactly as many comma-separated fields as the
header. The patients files contain no quote characters (verified), so a
plain split on ',' is exact and clean lines are written through byte-for-byte.

Outputs (per batch NN), next to the input:
  patients_clean.csv.gz     header + clean lines, unchanged
  patients_rejects.csv.gz   SOURCE_FILE,SOURCE_LINE,FIELD_COUNT,RAW_LINE

Usage:  python3 -I quarantine_patients.py [~/synthea_work/csv]
"""
import csv
import glob
import gzip
import os
import sys

root = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/synthea_work/csv")
total_clean = total_rejects = 0

for src in sorted(glob.glob(os.path.join(root, "batch_*", "patients.csv.gz"))):
    batch = os.path.basename(os.path.dirname(src))            # batch_NN
    s3_name = f"{batch}__patients.csv.gz"                       # original S3 file name
    out_clean = os.path.join(os.path.dirname(src), "patients_clean.csv.gz")
    out_rej = os.path.join(os.path.dirname(src), "patients_rejects.csv.gz")

    clean = rejects = 0
    with gzip.open(src, "rt", encoding="utf-8", newline="") as fin, \
         gzip.open(out_clean, "wt", encoding="utf-8", newline="") as fc, \
         gzip.open(out_rej, "wt", encoding="utf-8", newline="") as fr:
        header = fin.readline()
        if '"' in header:
            sys.exit(f"{src}: quotes found - plain comma split is no longer exact")
        n_fields = header.rstrip("\r\n").count(",") + 1
        fc.write(header)
        rej = csv.writer(fr, lineterminator="\n")
        rej.writerow(["SOURCE_FILE", "SOURCE_LINE", "FIELD_COUNT", "RAW_LINE"])

        for line_no, line in enumerate(fin, start=2):          # line 1 = header
            body = line.rstrip("\r\n")
            if '"' in body:
                sys.exit(f"{src}:{line_no}: quotes found - plain comma split is no longer exact")
            fields = body.count(",") + 1 if body else 0
            if fields == n_fields:
                fc.write(line)
                clean += 1
            else:
                rej.writerow([s3_name, line_no, fields, body])
                rejects += 1

    total_clean += clean
    total_rejects += rejects
    print(f"{batch}: clean {clean:>8,}  rejects {rejects:>5,}")

print(f"TOTAL : clean {total_clean:>8,}  rejects {total_rejects:>5,}")
