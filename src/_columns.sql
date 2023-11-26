create function schema._columns(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    table_schema text,
    table_name text,
    order_by int,
    comment text,
    short_definition text,
    definition text
)
language sql
as
$$
select
    sub.type,
    sub.schema,
    sub.name,
    sub.table_schema,
    sub.table_name,
    sub.order_by,
    sub.comment,
    sub.definition as short_definition,
    concat(
        'ALTER TABLE ',
        schema._ident(sub.table_schema, sub.table_name),
        ' ADD COLUMN ',
        sub.definition, 
        ';',
        case when sub.comment is not null then concat(
            E'\n',
            'COMMENT ON COLUMN ',
            schema._ident(sub.table_schema, sub.table_name), '.', quote_ident(sub.name),
            ' IS ',
            schema._quote(sub.comment),
            ';'
        ) else '' end
    ) as definition
from (
    select
        'column' as type,
        c.table_schema::text as schema,
        c.column_name::text as name,
        c.table_schema::text as table_schema,
        c.table_name::text as table_name,
        c.ordinal_position as order_by,
        pgdesc.description as comment,
        concat(
            quote_ident(c.column_name),
            ' ',
            (c.udt_schema || '.' || c.udt_name)::regtype::text,
            ' ',
            schema._parse_column(c)
        ) as definition
    from 
        information_schema.columns c
        join information_schema.tables t
            on c.table_schema = t.table_schema and c.table_name = t.table_name and t.table_type = 'BASE TABLE'
        left outer join pg_catalog.pg_statio_user_tables pgtbl
            on pgtbl.schemaname = c.table_schema and c.table_name = pgtbl.relname
        left outer join pg_catalog.pg_description pgdesc
            on pgtbl.relid = pgdesc.objoid and c.ordinal_position = pgdesc.objsubid
    where 
        c.table_schema = any(_schemas)
) sub
$$;
