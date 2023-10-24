create function schema._routines_order(_schemas text[])
returns table (
    specific_schema text,
    specific_name text,
    order_by numeric
)
language sql
as
$$
with recursive cte as (
    select 
        r.specific_schema,
        r.specific_name,
        r.external_language,
        u.routine_schema,
        u.routine_name, 
        1::numeric + (case when r.external_language = 'SQL' then 0 else 0.5 end) as order_by
    from
        information_schema.routines r
        left join information_schema.routine_routine_usage u using (specific_schema, specific_name)
    where 
        u.routine_schema is null and r.specific_schema = any(_schemas)

    union all 

    select 
        r.specific_schema,
        r.specific_name,
        r.external_language,
        u.routine_schema,
        u.routine_name, 
        cte.order_by - 1 + (case when r.external_language = 'SQL' then 0 else 0.5 end) as order_by
    from
        information_schema.routines r
        join information_schema.routine_routine_usage u 
        on r.specific_schema = u.specific_schema and r.specific_name = u.specific_name
        join cte 
        on u.routine_schema = cte.specific_schema and u.routine_name = cte.specific_name
    where 
        r.specific_schema = any(_schemas)
)
select
    cte.specific_schema,
    cte.specific_name,
    cte.order_by
from cte
$$;