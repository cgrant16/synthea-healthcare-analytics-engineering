{#
  generate_schema_name - use a model's custom schema exactly as written.
  Author: Cortwright Grant

  dbt's default concatenates "<target schema>_<custom schema>" (e.g.
  STAGING_MARTS). This project builds into fixed, pre-created schemas
  (STAGING / INTERMEDIATE / MARTS) that SYNTHEA_DBT_ROLE has CREATE rights
  on, and the role cannot create new schemas, so the custom schema is used
  verbatim. Models without a custom schema fall back to the target schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
