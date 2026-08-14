{#
    Medallion layers (bronze/silver/gold) must land in a fixed schema name
    regardless of which environment target is active. Isolation between
    dev/prod is provided by the target database (DEV_DB vs PROD_DB), not by
    schema prefixing, so this overrides dbt's default
    "<target_schema>_<custom_schema>" behavior.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
