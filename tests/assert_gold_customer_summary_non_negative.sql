-- Singular test: fails if any row is returned.
-- new_customers is a count and must never be negative.
select *
from {{ ref('gold_customer_summary') }}
where new_customers < 0
