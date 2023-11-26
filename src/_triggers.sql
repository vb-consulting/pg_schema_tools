create function schema._triggers(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    table_schema text,
    table_name text,
    comment text,
    definition text
)
language sql
as
$$
select 
    'trigger' as type,
    trigger_schema::text as schema,
    trigger_name::text as name,
    event_object_schema::text as table_schema,
    event_object_table::text as table_name,
    null::text as comment,
    pg_get_triggerdef(oid) || ';' as definition
from 
    (
        select distinct trigger_schema, trigger_name, event_object_schema, event_object_table 
        from information_schema.triggers
        where
            event_object_schema = any(_schemas)
    ) tr
    join pg_trigger pg 
        on tr.trigger_name = pg.tgname
        and (quote_ident(event_object_schema) || '.' || quote_ident(event_object_table))::regclass::oid = tgrelid
$$;
