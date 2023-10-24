create function schema._extensions()
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
    'extension' as type,
    null as schema,
    e.extname as name,
    a.comment,
    concat(
        'CREATE EXTENSION ',
        quote_ident(e.extname),
        ';'
    ) as definition
from 
    pg_extension e 
    join pg_available_extensions a on e.extname = a.name
where e.extname <> 'plpgsql'
$$;