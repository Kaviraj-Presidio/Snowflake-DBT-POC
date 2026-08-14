-- Bronze: source-conformed, minimally transformed (rename/cast only).
with source as (

    select * from {{ ref('raw_customers') }}

)

select
    id as customer_id,
    nullif(trim(first_name), '') as first_name,
    nullif(trim(last_name), '') as last_name,
    nullif(trim(email), '') as email,
    created_at::timestamp as created_at

from source
