-- stg_synthea_2026__payers - one row per payer, typed and renamed.
-- Ten rows. One is the NO_INSURANCE placeholder that Synthea assigns to encounters
-- of uninsured patients. The amount and count columns are Synthea's own lifetime
-- totals per payer.
-- Author: Cortwright Grant

with source as (

    select * from {{ source('synthea_2026_raw', 'payers') }}

)

select
    id                                              as payer_id,
    name                                            as payer_name,
    ownership,                                                              -- GOVERNMENT | PRIVATE | NO_INSURANCE
    address,
    city,
    state_headquartered,
    zip                                             as zip_code,
    phone,
    try_to_number(amount_covered, 38, 2)            as amount_covered,
    try_to_number(amount_uncovered, 38, 2)          as amount_uncovered,
    try_to_number(revenue, 38, 2)                   as revenue,
    try_to_number(covered_encounters)               as covered_encounters,
    try_to_number(uncovered_encounters)             as uncovered_encounters,
    try_to_number(covered_medications)              as covered_medications,
    try_to_number(uncovered_medications)            as uncovered_medications,
    try_to_number(covered_procedures)               as covered_procedures,
    try_to_number(uncovered_procedures)             as uncovered_procedures,
    try_to_number(covered_immunizations)            as covered_immunizations,
    try_to_number(uncovered_immunizations)          as uncovered_immunizations,
    try_to_number(unique_customers)                 as unique_customers,
    try_to_double(qols_avg)                         as qols_avg,
    try_to_number(member_months)                    as member_months,
    _source_file,
    _source_row,
    _loaded_at
from source
