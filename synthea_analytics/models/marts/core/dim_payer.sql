-- dim_payer - one row per payer.
-- Author: Cortwright Grant
--
-- Built straight from staging: payers belong to the claims domain, which is not
-- mapped to Tuva. Ten rows, one of them "No Insurance", which Synthea assigns to
-- encounters of uninsured patients - so every encounter has a payer, and
-- is_insured separates real coverage from that placeholder.
--
-- Synthea's lifetime totals per payer (amount covered, member months and so on)
-- are left in staging. They are pre-aggregated, and the facts are the place to
-- measure from.

select
    payer_id,
    iff(payer_name = 'NO_INSURANCE', 'No Insurance', payer_name)   as payer_name,
    case ownership
        when 'GOVERNMENT'   then 'government'
        when 'PRIVATE'      then 'private'
        when 'NO_INSURANCE' then 'no insurance'
    end                                                             as payer_type,
    ownership <> 'NO_INSURANCE'                                     as is_insured
from {{ ref('stg_synthea_2026__payers') }}
