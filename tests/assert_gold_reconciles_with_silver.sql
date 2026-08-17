-- Singular test: fails if any row is returned.
-- Reconciliation check across the medallion layers: every silver customer
-- must be accounted for in exactly one gold summary row, with no drift
-- introduced by the silver -> gold aggregation.
with silver_total as (

    select count(*) as customer_count
    from {{ ref('silver_customers') }}

),

gold_total as (

    select coalesce(sum(new_customers), 0) as customer_count
    from {{ ref('gold_customer_summary') }}

)

select
    silver_total.customer_count as silver_customer_count,
    gold_total.customer_count as gold_customer_count
from silver_total
cross join gold_total
where silver_total.customer_count != gold_total.customer_count
