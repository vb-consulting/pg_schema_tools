create function schema.views(_schemas text[] = schema._get_schema_array(null))
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
    case when c.relkind = 'v' then 'view' when c.relkind = 'm' then 'materialized view' end as type,
    n.nspname::text as schema,
    c.relname::text as name, 
    pgdesc.description as comment,
    concat(
        'CREATE ',
        case when c.relkind = 'v' then 'VIEW ' when c.relkind = 'm' then 'MATERIALIZED VIEW ' end,
        schema._ident(n.nspname, c.relname),
        case when c.reloptions is null then '' else ' WITH (' || array_to_string(c.reloptions, ', ') || ')' end,
        E' AS\n',
        pg_get_viewdef((quote_ident(n.nspname) || '.' || quote_ident(c.relname))::regclass, true),
        case when pgdesc.description is not null then E'\n\n' || concat(
            'COMMENT ON ',
            case when c.relkind = 'v' then 'VIEW ' when c.relkind = 'm' then 'MATERIALIZED VIEW ' end,
            schema._ident(n.nspname, c.relname),
            ' IS ',
            schema.quote(pgdesc.description),
            ';'
        ) else '' end,
        E'\n'
    ) as definition
from 
    pg_catalog.pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_catalog.pg_description pgdesc
    on c.oid = pgdesc.objoid and pgdesc.objsubid = 0
where 
    c.relkind in ('v', 'm')
    and n.nspname = any(_schemas)
$$;