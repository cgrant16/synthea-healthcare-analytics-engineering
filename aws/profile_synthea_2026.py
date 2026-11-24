#!/usr/bin/env python3
"""
profile_synthea_2026.py - profile the generated Synthea CSVs BEFORE they are loaded.
Author: Cortwright Grant

Why: the load into RAW_2026 matches columns by name with
ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE, so a row with the wrong number of
fields would load silently (that is how the 2017 patients defect got in - see
quarantine_patients.py). This script proves, on the source files, that every
row has exactly the header's field count, and prints the row counts that
snowflake/06_raw_2026_verification.sql must reproduce.

It also checks the keys the dbt source tests rely on:
  * ids are unique and non-empty in the entity tables
  * every foreign key on encounters, providers, payer_transitions and claims
    resolves to a row in its parent table

claims_transactions is only counted and field-checked here (its ids would not
fit comfortably in memory); its uniqueness and its link to claims are tested in
Snowflake by dbt.

Usage:  python3 profile_synthea_2026.py [csv_dir]
        csv_dir defaults to ~/synthea_work/synthea_latest_10k/out/csv
Exit code 1 if any check fails.
"""
import csv
import glob
import os
import sys
from collections import defaultdict
from multiprocessing import Pool

csv.field_size_limit(10 ** 9)

# table -> id column to collect (must be unique and non-empty)
ID_COLUMNS = {
    "patients": "Id", "organizations": "Id", "providers": "Id", "payers": "Id",
    "encounters": "Id", "claims": "Id",
}
# (child table, child column, parent table) - every value must exist in the parent's ids
FOREIGN_KEYS = [
    ("encounters", "PATIENT", "patients"),
    ("encounters", "ORGANIZATION", "organizations"),
    ("encounters", "PROVIDER", "providers"),
    ("encounters", "PAYER", "payers"),
    ("providers", "ORGANIZATION", "organizations"),
    ("payer_transitions", "PATIENT", "patients"),
    ("payer_transitions", "PAYER", "payers"),
    ("claims", "PATIENTID", "patients"),
    ("claims", "PROVIDERID", "providers"),
    ("claims", "APPOINTMENTID", "encounters"),
]
FK_COLUMNS = defaultdict(list)
for child, column, _parent in FOREIGN_KEYS:
    FK_COLUMNS[child].append(column)


def table_of(path):
    """claims_transactions-12.csv -> claims_transactions"""
    return os.path.basename(path)[:-4].rsplit("-", 1)[0]


def scan(path):
    """One CSV part: rows, rows with a wrong field count, ids and distinct FK values."""
    table = table_of(path)
    id_col = ID_COLUMNS.get(table)
    fk_cols = FK_COLUMNS.get(table, [])
    rows = bad = empty_ids = 0
    ids = []
    fk_values = {c: set() for c in fk_cols}
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        width = len(header)
        id_pos = header.index(id_col) if id_col else None
        fk_pos = [(c, header.index(c)) for c in fk_cols]
        for row in reader:
            rows += 1
            if len(row) != width:
                bad += 1
                continue
            if id_pos is not None:
                if row[id_pos]:
                    ids.append(row[id_pos])
                else:
                    empty_ids += 1
            for column, pos in fk_pos:
                fk_values[column].add(row[pos])
    return table, header, rows, bad, empty_ids, ids, fk_values


def main():
    default_dir = os.path.expanduser("~/synthea_work/synthea_latest_10k/out/csv")
    csv_dir = sys.argv[1] if len(sys.argv) > 1 else default_dir
    paths = sorted(glob.glob(os.path.join(csv_dir, "*.csv")))
    if not paths:
        sys.exit(f"No CSV files in {csv_dir}")

    parts = defaultdict(int)
    rows = defaultdict(int)
    bad = defaultdict(int)
    empty_ids = defaultdict(int)
    headers = defaultdict(set)
    ids = defaultdict(list)
    fk_values = defaultdict(lambda: defaultdict(set))

    with Pool() as pool:
        for table, header, n, n_bad, n_empty, part_ids, part_fks in pool.imap_unordered(scan, paths):
            parts[table] += 1
            rows[table] += n
            bad[table] += n_bad
            empty_ids[table] += n_empty
            headers[table].add(tuple(header))
            ids[table].extend(part_ids)
            for column, values in part_fks.items():
                fk_values[table][column] |= values

    failures = 0
    print(f"{'table':<20} {'parts':>5} {'rows':>12} {'cols':>5} {'bad field count':>16}")
    for table in sorted(rows):
        flag = ""
        if bad[table] or len(headers[table]) != 1:
            flag = "  <-- FAIL"
            failures += 1
        cols = len(next(iter(headers[table])))
        print(f"{table:<20} {parts[table]:>5} {rows[table]:>12,} {cols:>5} {bad[table]:>16,}{flag}")
    print(f"{'TOTAL':<20} {sum(parts.values()):>5} {sum(rows.values()):>12,}")

    print("\nPrimary keys (rows = distinct ids, no empty ids):")
    id_sets = {}
    for table in ID_COLUMNS:
        id_sets[table] = set(ids[table])
        ok = len(id_sets[table]) == rows[table] and empty_ids[table] == 0
        failures += 0 if ok else 1
        print(f"  {table:<16} rows {rows[table]:>10,}  distinct ids {len(id_sets[table]):>10,}"
              f"  empty {empty_ids[table]:>3}  {'OK' if ok else 'FAIL'}")

    print("\nForeign keys (distinct values missing from the parent table):")
    for child, column, parent in FOREIGN_KEYS:
        missing = fk_values[child][column] - id_sets[parent]
        failures += 0 if not missing else 1
        sample = f"  e.g. {sorted(missing)[:2]}" if missing else ""
        print(f"  {child + '.' + column:<32} -> {parent:<14} missing {len(missing):>6,}"
              f"  {'OK' if not missing else 'FAIL'}{sample}")

    print("\nRESULT:", "all checks passed" if failures == 0 else f"{failures} check(s) FAILED")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
