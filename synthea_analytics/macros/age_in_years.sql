{#
  age_in_years - completed years between a birth date and an as-of date.
  Author: Cortwright Grant

  datediff(year, ...) only counts calendar-year boundaries, so someone born in
  December is "1" the following January. This subtracts a year when the
  birthday has not yet been reached in the as-of year.

  Usage:  {{ age_in_years('birth_date', 'encounter_start_date') }}
#}
{% macro age_in_years(birth_date, as_of_date) -%}
    (
        datediff(year, {{ birth_date }}, {{ as_of_date }})
        - iff(
            dateadd(year, datediff(year, {{ birth_date }}, {{ as_of_date }}), {{ birth_date }}) > {{ as_of_date }},
            1,
            0
          )
    )
{%- endmacro %}
