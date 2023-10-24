create function schema._views_order(_schemas text[])
returns table (
    schema text,
    name text,
    order_by numeric
)
language sql
as
$$
with recursive view_usage_cte as (
    select view_schema, view_name, table_schema, table_name
    from information_schema.view_table_usage u
    join information_schema.views v using(table_schema, table_name)
    where view_schema = any(_schemas)
),
rec_cte as (
    select 
        v.table_schema as view_schema, 
        v.table_name as view_name,
        u.view_schema as table_schema, 
        u.view_name as table_name,
        1 as order_by
    from
        information_schema.views v
        left join view_usage_cte u on v.table_schema = u.view_schema and v.table_name = u.view_name
    where 
        u.view_schema is null and v.table_schema = any(_schemas)

    union all 

    select 
        u.view_schema, 
        u.view_name,
        u.table_schema, 
        u.table_name,
        c.order_by + 1 as order_by
    from
        view_usage_cte u
        join rec_cte c on u.table_schema = c.view_schema and u.table_name = c.view_name
    where 
        u.table_schema = any(_schemas)
)
select
    c.view_schema as schema, 
    c.view_name as name,
    c.order_by
from rec_cte c
$$;