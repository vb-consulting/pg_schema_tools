create function schema._create_table_temp_tables(
    _schemas text[],
    _create_columns boolean = true,
    _create_constraints boolean = true,
    _create_indexes boolean = true,
    _create_triggers boolean = true,
    _create_policies boolean = true,
    _create_sequences boolean = true
)
returns void
language plpgsql
as 
$$
begin
    if _create_columns then
        create temp table _columns on commit drop as
        select  
            t.type,
            t.schema,
            t.name,
            t.table_schema,
            t.table_name,
            t.order_by,
            t.comment,
            t.short_definition,
            t.definition
        from schema.columns(_schemas) t;
    end if;
    if _create_constraints then
        create temp table _constraints on commit drop as
        select  
            t.type,
            t.order_by,
            t.schema,
            t.name,
            t.table_schema,
            t.table_name,
            t.comment,
            t.short_definition,
            t.definition
        from schema.constraints(_schemas) t;
    end if;
    if _create_indexes then
        create temp table _indexes on commit drop as
        select  
            t.type,
            t.schema,
            t.name,
            t.table_schema,
            t.table_name,
            t.comment,
            t.definition
        from schema.indexes(_schemas) t;
    end if;
    if _create_triggers then
        create temp table _triggers on commit drop as
        select  
            t.type,
            t.schema,
            t.name,
            t.table_schema,
            t.table_name,
            t.comment,
            t.definition
        from schema.triggers(_schemas) t;
    end if;
    if _create_policies then
        create temp table _policies on commit drop as
        select  
            t.type,
            t.schema,
            t.name,
            t.table_schema,
            t.table_name,
            t.comment,
            t.definition
        from schema.policies(_schemas) t;
    end if;
    if _create_sequences then
        create temp table _sequences on commit drop as
        select
            t.type,
            t.schema,
            t.name,
            t.table_schema,
            t.table_name,
            t.column_name,
            t.comment,
            t.definition
        from schema.sequences(_schemas) t;
    end if;
end;
$$;