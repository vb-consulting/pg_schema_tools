create function schema.dump(
    _schema text = null,
    _type text = null,
    _search text = null,
    
    _include_header boolean = true,
    _include_transaction boolean = true,
    
    _include_extensions boolean = true,
    _include_schemas boolean = true,
    
    _include_types boolean = true,
    _include_enums boolean = true,
    _include_domains boolean = true,
    
    _include_tables boolean = true,
    _include_sequences boolean = true,
    _include_constraints boolean = true,
    _include_indexes boolean = true,

    _include_triggers boolean = true,
    _include_policies boolean = true,
    
    _include_views boolean = true,
    _include_routines boolean = true,
    _include_rules boolean = true,
    
    _single_row boolean = false
)
returns table (line text)
language plpgsql
as 
$$
declare 
    _schemas text[];
    _count bigint;
begin
    select p._schema, p._type, p._search 
    into _schema, _type, _search 
    from schema._prepare_params(_schema, _type, _search) p;

    _schemas = schema._get_schema_array(_schema);
    if _schemas is null or _schemas = '{}' then
        raise exception 'No schema found for expression: %s', _schema;
    end if;
    
    if schema._temp_exists('dump') then
        drop table pg_temp.dump;
    end if;
    create temp table pg_temp.dump(number int not null generated always as identity, line text not null);    

    create or replace function pg_temp.lines(variadic text[])
    returns void
    language sql
    as 
    $line$
    insert into pg_temp.dump (line) select unnest($1) as line
    $line$;

    if _include_header then
        perform pg_temp.lines(
            '--',
            format('-- Schema dump for schema%s: %s', case when array_length(_schemas, 1) = 1 then '' else 's' end, array_to_string(_schemas, ', ')),
            format('-- Instance: %s@%s:%s/%s', 
                current_user,
                (select setting from pg_settings where name = 'listen_addresses'), 
                (select setting from pg_settings where name = 'port'),
                current_database()
            ),
            format('-- Timestamp: %s', now()),
            '--',
            ''
        );
    end if;
    
    if _include_transaction then
        perform pg_temp.lines('BEGIN;', '');
    end if;

    if _include_extensions then
        create temp table extensions_tmp on commit drop as
        select t.definition from schema._extensions() t where schema._search_filter(t, _type, _search) order by t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- extensions');
            perform pg_temp.lines(definition) from extensions_tmp;
            perform pg_temp.lines('');
        end if;
    end if;
    
    if _include_schemas then
        create temp table schemas_tmp on commit drop as
        select format('CREATE SCHEMA %I;', s) as definition from unnest(_schemas) s where s <> 'public' order by s;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- schemas');
            perform pg_temp.lines(definition) from schemas_tmp;
            perform pg_temp.lines('');
        end if;
    end if;
    
    if _include_types then
        create temp table types_tmp on commit drop as
        select t.definition from schema._types(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- types');
            perform pg_temp.lines(definition) from types_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_enums then
        create temp table enums_tmp on commit drop as
        select t.definition from schema._enums(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- enums');
            perform pg_temp.lines(definition) from enums_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_domains then
        create temp table domains_tmp on commit drop as
        select t.definition from schema._domains(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- domains');
            perform pg_temp.lines(definition) from domains_tmp;
            perform pg_temp.lines('');
        end if;
    end if;
    
    if _include_sequences then
        create temp table sequences_tmp on commit drop as
        select t.definition 
        from schema._sequences(_schemas) t 
        where schema._search_filter(t, _type, _search) and t.definition like 'CREATE %'
        order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- sequences');
            perform pg_temp.lines(definition) from sequences_tmp;
            perform pg_temp.lines('');
        end if;
    end if;
    
    if _include_tables then
        perform schema._create_table_temp_tables(_schemas);

        create temp table tables_tmp on commit drop as
        select t.schema, t.name, t.definition 
        from schema._tables(_schemas) t 
        where schema._search_filter(t, _type, _search) 
        order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- tables');
            perform pg_temp.lines(definition) from tables_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_routines then
        create temp table routines_tmp on commit drop as
        select t.type, t.definition from schema._routines(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- ' || (select string_agg(distinct type || 's', ', ') from routines_tmp));
            perform pg_temp.lines(definition) from routines_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_views then
        create temp table views_tmp on commit drop as
        select t.type, t.definition from schema._views(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- ' || (select string_agg(distinct type || 's', ', ') from views_tmp));
            perform pg_temp.lines(definition) from views_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_tables then
        if _include_sequences then
            create temp table sequence_owners_tmp on commit drop as
            select t1.definition 
            from _sequences t1 inner join tables_tmp t2 on t1.table_schema = t2.schema and t1.table_name = t2.name
            where t1.definition like 'ALTER SEQUENCE %'
            order by t1.schema, t1.name;
            
            get diagnostics _count = row_count;
            if _count > 0 then
                perform pg_temp.lines('-- sequence ownership');
                perform pg_temp.lines(definition) from sequence_owners_tmp;
                perform pg_temp.lines('');
            end if;
        end if;

        if _include_constraints then
            create temp table constraints_tmp on commit drop as
            select t1.type, t1.schema, t1.name, t1.order_by, t1.definition 
            from _constraints t1 
            inner join tables_tmp t2 on t1.table_schema = t2.schema and t1.table_name = t2.name;
            
            if (select count(*) from constraints_tmp where order_by = 1) > 0 then
                perform pg_temp.lines('-- primary keys');
                perform pg_temp.lines(definition) from constraints_tmp where order_by = 1 order by schema, name;
                perform pg_temp.lines('');
            end if;

            if (select count(*) from constraints_tmp where order_by = 2) > 0 then
                perform pg_temp.lines('-- unique constraints');
                perform pg_temp.lines(definition) from constraints_tmp where order_by = 2 order by schema, name;
                perform pg_temp.lines('');
            end if;

            if (select count(*) from constraints_tmp where order_by > 2) > 0 then
                perform pg_temp.lines('-- ' || (select string_agg(distinct type || 's', ', ') from constraints_tmp where order_by > 2));
                perform pg_temp.lines(definition) from constraints_tmp where order_by > 2 order by schema, name, type desc;
                perform pg_temp.lines('');
            end if;
        end if;

        if _include_indexes then
            create temp table indexes_tmp on commit drop as
            select t1.definition 
            from _indexes t1 
                inner join tables_tmp t2 on t1.table_schema = t2.schema and t1.table_name = t2.name
                left join _constraints c on t1.name = c.name and t1.table_schema = c.table_schema and t1.table_name = c.table_name
            where c.table_name is null
            order by t1.schema, t1.name;

            get diagnostics _count = row_count;
            if _count > 0 then
                perform pg_temp.lines('-- indexes');
                perform pg_temp.lines(definition) from indexes_tmp;
                perform pg_temp.lines('');
            end if;
        end if;

        if _include_triggers then
            create temp table triggers_tmp on commit drop as
            select t.definition from schema._triggers(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
            
            get diagnostics _count = row_count;
            if _count > 0 then
                perform pg_temp.lines('-- triggers');
                perform pg_temp.lines(definition) from triggers_tmp;
                perform pg_temp.lines('');
            end if;
        end if;

        if _include_policies then
            create temp table policies_tmp on commit drop as
            select t.definition from schema._policies(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
            
            get diagnostics _count = row_count;
            if _count > 0 then
                perform pg_temp.lines('-- policies');
                perform pg_temp.lines(definition) from policies_tmp;
                perform pg_temp.lines('');
            end if;
        end if;

    end if; -- if include tables

    if _include_rules then
            create temp table rules_tmp on commit drop as
            select t.definition from schema._rules(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
            
            get diagnostics _count = row_count;
            if _count > 0 then
                perform pg_temp.lines('-- rules');
                perform pg_temp.lines(definition) from rules_tmp;
                perform pg_temp.lines('');
            end if;
        end if;
        
    if _include_transaction then
        perform pg_temp.lines('END;');
    end if;
    
    if _single_row then
        return query
        select string_agg(d.line, E'\n' order by d.number asc) from pg_temp.dump d;
    else
        return query
        select d.line from pg_temp.dump d order by d.number asc;
    end if;
end;
$$;