create function schema._domains(_schemas text[])
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
        'domain' as type,
        n.nspname::text as schema,
        t.typname::text as name,
        pg_catalog.obj_description(t.oid, 'pg_type') as comment,
        concat(
            'CREATE DOMAIN ',
            schema._ident(n.nspname, t.typname),
            ' AS ',
            pg_catalog.format_type(t.typbasetype, t.typtypmod),
            case when t.typnotnull is true then ' NOT NULL' else '' end,
            case when t.typdefault is not null then ' DEFAULT ' || t.typdefault  else '' end,
            E'\n',
            c.definition,
            ';'
        ) as definition
    from 
        pg_catalog.pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        join lateral (
            select string_agg(
                concat(
                    '    ',
                    pg_catalog.pg_get_constraintdef(c.oid, true)
                ), E'\n'
            ) as definition
            from pg_catalog.pg_constraint c
            where 
                c.contypid = t.oid
        ) c on true
    where 
        t.typtype = 'd'
        and pg_catalog.pg_type_is_visible(t.oid)
        and n.nspname = any(_schemas)
) sub;
$$;