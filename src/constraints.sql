create function schema.constraints(_schemas text[] = schema._get_schema_array(null))
returns table (
    type text,
    order_by int,
    schema text,
    name text,
    table_schema text,
    table_name text,
    comment text,
    short_definition text,
    definition text
)
language sql
as
$$
select
    sub.type, 
    sub.order_by, 
    sub.schema, 
    sub.name, 
    sub.table_schema, 
    sub.table_name, 
    null::text as comment,
    concat(
        'CONSTRAINT ',
        sub.name,
        ' ',
        sub.definition
    ) as short_definition,
    concat(
        'ALTER TABLE ONLY ',
        quote_ident(sub.table_schema),
        '.',
        quote_ident(sub.table_name),
        ' ADD CONSTRAINT ',
        sub.name,
        ' ',
        sub.definition,
        ';'
    ) as definition
from (
    select
        lower(constraint_type) as type,
        case 
            when pgc.contype = 'p' then 1
            when pgc.contype = 'u' then 2
            when pgc.contype = 'c' then 3
            when pgc.contype = 'f' then 4
            else 5
        end as order_by,
        quote_ident(constraint_schema) as schema,
        quote_ident(constraint_name) as name,
        table_schema::text,
        table_name::text,
        pg_get_constraintdef(pgc.oid, true) as definition
    from 
        information_schema.table_constraints tc 
        join pg_constraint pgc 
            on tc.constraint_name = pgc.conname 
            and quote_ident(constraint_schema)::regnamespace::oid = connamespace
            and (quote_ident(table_schema) || '.' || quote_ident(table_name))::regclass::oid = conrelid
    where
        table_schema = any(_schemas)
) sub
$$;