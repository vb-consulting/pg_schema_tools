create function schema.search(
    _schema text = null,
    _type text = null,
    _search text = null
)
returns table (
    type text,
    schema text,
    name text,
    comment text,
    definition text
)
language plpgsql
as 
$$
declare 
    _schemas text[];
begin
    select p._schema, p._type, p._search 
    into _schema, _type, _search 
    from schema._prepare_params(_schema, _type, _search) p;
    
    _schemas = schema._get_schema_array(_schema);
    if _schemas is null or _schemas = '{}' then
        raise exception 'No schema found for expression: %', _schema;
    end if;
    
    if schema._temp_exists('search') then
        drop table pg_temp.search;
    end if;
    
    create temp table pg_temp.search as
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._extensions() t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._types(_schemas) t
    where
        schema._search_filter(t, _type, _search);
        
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._enums(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._domains(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    perform schema._create_table_temp_tables(_schemas);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._tables_full(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select 
        sub.type,
        sub.schema,
        sub.name,
        sub.comment,
        sub.definition
    from (
        select
            t.type, 
            t.schema, 
            t.table_name || '.' || quote_ident(t.name) as name, 
            t.comment,
            t.definition
        from _columns t
    ) sub
    where
        schema._search_filter(sub, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition
    from _constraints t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition
    from _indexes t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition
    from _triggers t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition
    from _policies t
    where
        schema._search_filter(t, _type, _search);

    insert into pg_temp.search
    select 
        sub.type,
        sub.schema,
        sub.name,
        sub.comment,
        sub.definition
    from (
        select 
            t.type,
            t.schema,
            t.name,
            t.comment,
            string_agg(t.definition, E'\n') as definition
        from _sequences t
        group by
            t.type,
            t.schema,
            t.name,
            t.comment
    ) sub
    where
        schema._search_filter(sub, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._views(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._routines(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._rules(_schemas) t
    where
        schema._search_filter(t, _type, _search);

    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition
    from schema._aggregates(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    return query
    select 
        r.type, r.schema, r.name, r.comment, r.definition
    from pg_temp.search r
    order by 
        r.schema, r.type desc, r.name;
end;
$$;

comment on function schema.search(text, text, text) is 'Search and retrieve the schema objects in the database.';