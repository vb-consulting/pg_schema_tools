create function schema._ranges(_schemas text[])
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
    'range' as type,
    sub.schema,
    sub.name,
    sub.comment,
    concat(
        'CREATE TYPE ',
        schema._ident(sub.schema, sub.name),
        E' AS RANGE (\n',
        '    SUBTYPE = ', SUBTYPE,
        case when SUBTYPE_OPCLASS <> '-' and SUBTYPE_OPCLASS not like 'pg_%' then E',\n    SUBTYPE_OPCLASS = ' || SUBTYPE_OPCLASS else '' end,
        case when sub.COLLATION <> '-' and sub.COLLATION not like 'pg_%' then E',\n    COLLATION = ' || sub.COLLATION else '' end,
        case when CANONICAL <> '-' and CANONICAL not like 'pg_%' then E',\n    CANONICAL = ' || CANONICAL else '' end,
        case when SUBTYPE_DIFF <> '-' and SUBTYPE_DIFF not like 'pg_%' then E',\n    SUBTYPE_DIFF = ' || SUBTYPE_DIFF else '' end,
        case when MULTIRANGE_TYPE_NAME <> '-' and MULTIRANGE_TYPE_NAME not like 'pg_%' then E',\n    MULTIRANGE_TYPE_NAME = ' || MULTIRANGE_TYPE_NAME else '' end,
        E'\n);',
        case when sub.comment is null then '' else
            concat(
                E'\n',
                'COMMENT ON TYPE ',
                schema._ident(sub.schema, sub.name),
                ' IS ',
                schema._quote(sub.comment),
                E';'
            )
        end
    ) as definition
from (
    select
        n.nspname::text as schema,
        t.typname::text as name,
        pg_catalog.obj_description(t.oid, 'pg_type') as comment,
        r.rngsubtype::regtype::text as SUBTYPE, 
        r.rngsubopc::regtype::text as SUBTYPE_OPCLASS, 
        r.rngcollation::regtype::text as COLLATION, 
        r.rngcanonical::regproc::text as CANONICAL, 
        r.rngsubdiff::regproc::text as SUBTYPE_DIFF, 
        r.rngmultitypid::regtype::text as MULTIRANGE_TYPE_NAME
    from 
        pg_catalog.pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        join pg_catalog.pg_range r on t.oid = r.rngtypid 
    where 
        t.typtype = 'r'
        and n.nspname = any(_schemas)
) sub
$$;
