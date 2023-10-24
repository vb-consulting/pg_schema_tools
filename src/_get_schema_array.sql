create function schema._get_schema_array(text)
returns text[]
language sql
as 
$$
select
    array_agg(nspname::text)
from
    pg_namespace
where
    nspname not like 'pg_%' 
    and nspname <> 'information_schema' 
    /* and nspname <> 'schema' */
    and ($1 is null or nspname similar to $1);
$$;