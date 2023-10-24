create function schema._temp_exists(text)
returns boolean
language sql
as 
$$
select exists(
    select 1 from information_schema.tables t
    where t.table_name = $1 and table_type = 'LOCAL TEMPORARY'
)
$$;