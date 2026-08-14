-- Gold: aggregated, consumption-ready mart.
with silver as (

    select * from {{ ref('silver_customers') }}

)

select
    date_trunc('month', created_at) as signup_month,
    count(*) as new_customers
from silver
group by 1
