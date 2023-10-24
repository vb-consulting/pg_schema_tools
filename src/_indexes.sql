create function schema._indexes(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    table_schema text,
    table_name text,
    comment text,
    definition text
)
language sql
as
$$
select 
    case when position(' UNIQUE ' in indexdef) > 0 then 'unique ' else ''end ||
    split_part(split_part(indexdef, 'USING ', 2), ' ', 1) || ' ' ||
    'index' as type,
    i.schemaname::text as schema,
    i.indexname::text as name, 
    i.schemaname::text as table_schema,
    i.tablename::text as table_name, 
    null::text as comment,
    indexdef || ';' as definition
from 
    pg_indexes i
where 
    i.schemaname = any(_schemas)
$$;