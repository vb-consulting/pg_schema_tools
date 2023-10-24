create function schema._enums(_schemas text[])
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
            schema._quote(sub.comment),
            ';'
        )
    end as definition
from (
    select 
        'enum' as type,
        n.nspname::text as schema,
        t.typname::text as name,
        pg_catalog.obj_description(t.oid, 'pg_type') as comment,
        concat(
            'CREATE TYPE ',
            schema._ident(n.nspname, t.typname),
            E' AS ENUM (\n',
            e.definition,
            E'\n);'
        ) as definition
    from 
        pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        join lateral (
            select string_agg(
                concat(
                    '    ',
                    schema._quote(e.enumlabel)
                ), E',\n' order by e.enumsortorder
            ) as definition
            from pg_catalog.pg_enum e
            where 
                e.enumtypid = t.oid
        ) e on true
    where
        t.typtype = 'e' 
        and n.nspname = any(_schemas)
) sub;
$$;