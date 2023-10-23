create function schema.rules(_schemas text[] = schema._get_schema_array(null))
returns table (
    type text,
    schema text,
    name text,
    comment text,
    definition text
)
language sql
as
$$
select
    'rule' as type,
    r.schemaname::text as schema,
    r.rulename::text as name,
    null as comment,
    r.definition
from 
    pg_catalog.pg_rules r
where 
    schemaname = any(_schemas)
$$;