-- dim_date - one row per calendar day.
-- Author: Cortwright Grant
--
-- Runs from 1915-01-01, the year of the oldest record in the dataset (Synthea
-- keeps each patient's full history), to the end of the current year. Every date
-- column in the fact tables joins to date_day; relationship tests on the facts
-- fail if a date ever falls outside this range.

with days as (

    {{ dbt_utils.date_spine(
        datepart   = "day",
        start_date = "to_date('1915-01-01')",
        end_date   = "dateadd(year, 1, date_trunc('year', current_date))"
    ) }}

),

typed as (

    select cast(date_day as date) as date_day from days

)

select
    date_day,
    year(date_day)                              as year_number,
    quarter(date_day)                           as quarter_number,
    month(date_day)                             as month_number,
    to_char(date_day, 'MMMM')                   as month_name,
    to_char(date_day, 'YYYY-MM')                as year_month,
    year(date_day) || '-Q' || quarter(date_day) as year_quarter,
    weekiso(date_day)                           as iso_week_number,
    day(date_day)                               as day_of_month,
    dayofyear(date_day)                         as day_of_year,
    dayofweekiso(date_day)                      as iso_day_of_week,     -- 1 = Monday ... 7 = Sunday
    decode(dayofweekiso(date_day),
           1, 'Monday', 2, 'Tuesday', 3, 'Wednesday', 4, 'Thursday',
           5, 'Friday', 6, 'Saturday', 7, 'Sunday') as day_name,
    dayofweekiso(date_day) in (6, 7)            as is_weekend,
    date_trunc('month', date_day)               as month_start_date,
    date_trunc('quarter', date_day)             as quarter_start_date,
    date_trunc('year', date_day)                as year_start_date
from typed
