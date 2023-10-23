create function schema.types(_schemas text[] = schema._get_schema_array(null))
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
    sub.type,
    sub.schema,
    sub.name,
    sub.comment,
    case when sub.comment is null then sub.definition else
        concat(
            sub.definition,
            E'\n',
            'COMMENT ON TYPE ',
            schema._ident(sub.schema, sub.name),
            ' IS ',
            schema.quote(sub.comment),
            ';'
        )
    end as definition
from (
    select
        'type' as type,
        n.nspname::text as schema,
        t.typname::text as name,
        pg_catalog.obj_description(t.oid, 'pg_type') as comment,
        concat(
            'CREATE TYPE ',
            schema._ident(n.nspname, t.typname),
            E' AS (\n',
            a.definition,
            E'\n);'
        ) as definition
    from 
        pg_catalog.pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        join pg_catalog.pg_class c on t.typrelid = c.oid and c.relkind = 'c'
        join lateral (
            select string_agg(
                concat(
                    '    ',
                    quote_ident(a.attname),
                    ' ',
                    pg_catalog.format_type(a.atttypid, a.atttypmod)
                ), E',\n' order by a.attnum
            ) as definition
            from pg_catalog.pg_attribute a
            where 
                a.attrelid = t.typrelid and a.attisdropped is false   
        ) a on true
    where 
        n.nspname = any(_schemas)
) sub;
$$;