create function schema._constraints(_schemas text[])
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
    sub.schema as table_schema, 
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
        quote_ident(sub.schema),
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
        case 
            when contype = 'p' then 'primary key constraint'
            when contype = 'u' then 'unique constraint'
            when contype = 'c' then 'check constraint'
            when contype = 'f' then 'foreign key constraint'
            when contype = 't' then 'trigger constraint'
            when contype = 'x' then 'exclusion constraint'
            else 'unknown constraint'
        end as type,
        case 
            when contype = 'p' then 1
            when contype = 'u' then 2
            when contype = 'c' then 3
            when contype = 'f' then 4
            else 5
        end as order_by,
        conname::text as name,
        connamespace::regnamespace::text as schema,
        conrelid::regclass::text as table_name,
        pg_get_constraintdef(oid, true) as definition
    from 
        pg_catalog.pg_constraint 
    where 
        connamespace::regnamespace::text = any(_schemas)
) sub
$$;