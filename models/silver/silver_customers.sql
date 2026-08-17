-- Silver: cleaned and conformed. Drops records that fail basic quality
-- rules rather than surfacing broken identities downstream.
with bronze as (

    select * from {{ ref('bronze_customers') }}

)

select
    customer_id,
    first_name,
    last_name,
    concat_ws(' ', last_name, first_name) as full_name,
    email,
    created_at
from bronze
where email is not null
