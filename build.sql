do
$install$
declare _t text;
begin

/* #region init */
if exists(select 1 as name from pg_namespace where nspname = 'schema') then
    --drop schema schema cascade;
    raise exception 'Schema "schema" already exists. Consider running "drop schema schema cascade;" to recreate schema schema.';
end if;

create schema schema;
/* #endregion init */

/* #region tables */
create view schema.tables as
select 
    sub.table_oid,
    sub.schema_name,
    sub.table_name,
    coalesce(
        array_agg(pk_att.attname::text order by pk_att.attnum) filter (where pk_att.attname is not null), 
        array[]::text[]
    ) as pk_column_names,
    coalesce(
        array_agg(pk_att.atttypid::regtype::text order by pk_att.attnum) filter (where pk_att.attname is not null), 
        array[]::text[]
    ) as pk_column_types,
    coalesce(
        array_agg(fk_att.attname::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as fk_column_names,
    coalesce(
        array_agg(fk_att.atttypid::regtype::text order by pk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as fk_column_types,
    coalesce(
        array_agg(ref_cl.oid order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::oid[]
    ) as ref_table_oids,
    coalesce(
        array_agg(ref_cl.relnamespace::regnamespace::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_schema_names,
    coalesce(
        array_agg(ref_cl.relname::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_table_names,
    coalesce(
        array_agg(ref_att.attname::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_column_names,
    coalesce(
        array_agg(ref_att.atttypid::regtype::text order by pk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_column_types
from (
        select 
            cl.oid as table_oid,
            cl.relnamespace::regnamespace::text as schema_name,
            cl.relname::text as table_name,
            con.contype,
            con.confrelid as fk_id,
            unnest(con.conkey) as column_attnum,
            unnest(con.confkey) as fk_column_attnum
        from 
            pg_catalog.pg_class cl
            left join pg_catalog.pg_constraint con on cl.oid = con.conrelid
        where
            cl.relnamespace::regnamespace::text not like 'pg_%' 
            and (con.contype = 'p' or con.contype = 'f')
    ) sub
    
    left join pg_attribute pk_att 
    on sub.table_oid = pk_att.attrelid and sub.column_attnum = pk_att.attnum and sub.contype = 'p'
        
    left join pg_attribute fk_att 
    on sub.table_oid = fk_att.attrelid and sub.column_attnum = fk_att.attnum and sub.contype = 'f'
    
    left join pg_class ref_cl on sub.fk_id = ref_cl.oid
    
    left join pg_attribute ref_att 
    on sub.fk_id = ref_att.attrelid and sub.fk_column_attnum = ref_att.attnum and sub.contype = 'f'

group by
    sub.table_oid,
    sub.schema_name,
    sub.table_name;
/* #endregion tables */

/* #region _prepare_params */
create function schema._prepare_params(
    inout _schema text,
    inout _type text,
    inout _search text
)
returns record
language plpgsql
as
$$
begin
    _schema = lower(trim(_schema));
    _type = lower(trim(_type));
    _search = lower(trim(_search));
    
    if _schema = '' then
        _schema = null;
    end if;
    
    if _type = '' then
        _type = null;
    end if;
    
    if _search = '' then
        _search = null;
    end if;
end;
$$;
/* #endregion _prepare_params */

/* #region _get_schema_array */
create function schema._get_schema_array(text)
returns text[]
language sql
as 
$$
select
    array_agg(nspname::text)
from
    pg_namespace
where
    nspname not like 'pg_%' 
    and nspname <> 'information_schema' 
    /* and nspname <> 'schema' */
    and ($1 is null or nspname similar to $1);
$$;
/* #endregion _get_schema_array */

/* #region _parse_column */
create function schema._parse_column(_c record)
returns text
language plpgsql
as
$$
declare 
    _identity text;
    _rec record;
begin
    if _c.is_identity = 'YES' then
        select
            seq.seqstart as start_value,
            seq.seqmin as min_value,
            seq.seqmax as max_value,
            seq.seqincrement as increment_by,
            seq.seqcycle as cycle,
            seq.seqcache as cache_size
        into _rec
        from   
            pg_catalog.pg_class cl
            join pg_catalog.pg_sequence seq on seq.seqrelid = cl.relfilenode
            join pg_catalog.pg_depend dep on seq.seqrelid = dep.objid
            join pg_catalog.pg_class depcl on dep.refobjid = depcl.relfilenode
            join pg_catalog.pg_attribute attrib on attrib.attnum = dep.refobjsubid and attrib.attrelid = dep.refobjid
        where 
            depcl.relnamespace::regnamespace::text = _c.table_schema 
            and depcl.relname = _c.table_name
            and attrib.attname = _c.column_name
        limit 1;
        
        _identity = concat(
            'GENERATED ', 
            _c.identity_generation, 
            ' AS IDENTITY (INCREMENT ',
            coalesce(_rec.increment_by::text, _c.identity_increment::text),
            ' START ',
            coalesce(_rec.start_value::text, _c.identity_start::text),
            ' MINVALUE ',
            coalesce(_rec.min_value::text, _c.identity_minimum::text),
            ' MAXVALUE ',
            coalesce(_rec.max_value::text, _c.identity_maximum::text),
            case when _rec is not null and _rec.cache_size <> 1 
                then ' CACHE ' || coalesce(_rec.cache_size::text, '1')
                else ''
            end,
            case when _rec.cycle is true or _c.identity_cycle = 'YES' then ' CYCLE)' else ')' end
        );
    end if;
    return concat(
        case when _c.is_nullable = 'NO' then 'NOT NULL ' else '' end,     
        case
            when _identity is not null then _identity
            when _c.is_generated <> 'NEVER' then 'GENERATED ' || _c.is_generated || ' AS ' || _c.generation_expression
            when _c.column_default is not null then 'DEFAULT ' || _c.column_default
        end
    );
end;
$$;
/* #endregion _parse_column */

/* #region _parse_return */
create function schema._parse_return(_oid oid, _specific_schema text, _specific_name text)
returns text
language plpgsql
as
$$
declare 
    _result text;
begin
    _result = pg_get_function_result(_oid);
    if _result = 'record' then
        _result = 'TABLE(' || E'\n    ' || (
            select string_agg(quote_ident(p.parameter_name) || ' ' || (p.udt_schema || '.' || p.udt_name)::regtype::text, E'\n    ' order by p.ordinal_position)
            from information_schema.parameters p 
            where p.specific_name = _specific_name and p.specific_schema = _specific_schema
        ) || E'\n)';
    end if;
    return _result;
end;
$$;
/* #endregion _parse_return */

/* #region _ident */
create function schema._ident(text, text, boolean = false)
returns text
language sql
as 
$$
select 
    case 
        when $3 then
            case when $1 = 'public' then '' else quote_ident($1) || '.' end || quote_ident($2)
        else
            quote_ident($1) || '.' || quote_ident($2)
    end
$$;
/* #endregion _ident */

/* #region _parse_routine_body */
create function schema._parse_routine_body(_body text, _signature text, _comment text)
returns text
language plpgsql
as
$$
declare 
    _line text;
    _quote text = '$' || '$';
    _count int = 0;
begin
    foreach _line in array string_to_array(_body, E'\n') loop
        if position(_quote in _line) > 0 then
            _count = _count + 1;
            _quote = '$' || repeat('_', _count) || '$';
        end if;
    end loop;
    return concat(
        _quote,
        _body,
        _quote,
        ';',
        case when _comment is not null then
            concat(
                E'\n\n'
                'COMMENT ON ',
                _signature,
                ' IS ',
                schema._quote(_comment),
                ';'
            )
        else
            ''
        end
    );
end;
$$;
/* #endregion _parse_routine_body */

/* #region _create_table_temp_tables */
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
        from schema._columns(_schemas) t;
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
        from schema._constraints(_schemas) t;
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
        from schema._indexes(_schemas) t;
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
        from schema._triggers(_schemas) t;
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
        from schema._policies(_schemas) t;
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
        from schema._sequences(_schemas) t;
    end if;
end;
$$;
/* #endregion _create_table_temp_tables */

/* #region _search_filter */
create or replace function schema._search_filter(
    _record record,
    _type text,
    _search text
)
returns boolean
language plpgsql
as 
$$
begin
    return (
        _type is null
        or _record.type = _type
        or _record.type similar to _type
    )
    and (
        _search is null 
        or _record.name = _search
        or _record.definition = _search
        or _record.comment = _search
        or lower(_record.name) similar to _search
        or lower(_record.definition) similar to _search
        or lower(_record.comment) similar to _search
    );
end;
$$;
/* #endregion _search_filter */

/* #region _quote */
create function schema._quote(text)
returns text
language sql
immutable
as 
$$
select case when position(E'\'' in $1) > 0 then 'E''' || replace($1, E'\'', '\''') || E'\'' else E'\'' || $1 || E'\'' end
$$;
/* #endregion _quote */

/* #region _aggregates */
create function schema._aggregates(_schemas text[])
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
    concat(
        sub.definition,
        case when sub.comment is null then '' else
            concat(
                E'\n',
                'COMMENT ON AGGREGATE ',
                sub.signature,
                ' IS ',
                schema._quote(sub.comment),
                E';'
            )
        end
    )
from (
    select
        'aggregate' as type,
        n.nspname as schema,
        p.proname as name,
        pg_catalog.obj_description(p.oid, 'pg_proc') as comment,
        format('%I.%I(%s)', n.nspname, p.proname, format_type(a.aggtranstype, null)) as signature,
        format(
            E'CREATE AGGREGATE %I.%I(%s) (\n%s\n);',
            n.nspname,
            p.proname,
            format_type(a.aggtranstype, null),
            array_to_string(
                array[
                    format('    SFUNC = %s', a.aggtransfn::regproc),
                    format('    STYPE = %s', format_type(a.aggtranstype, NULL)),
                    case a.aggfinalfn when '-'::regproc then null else format('    FINALFUNC = %s', a.aggfinalfn::text) end,
                    case a.aggsortop when 0 then null else format('    SORTOP = %s', op.oprname) end,
                    case when a.agginitval is null then null else format('    INITCOND = %s', a.agginitval) end
                ], E',\n'
            )
        ) as definition
    from 
        pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on p.pronamespace = n.oid
        join pg_catalog.pg_aggregate a on p.oid = a.aggfnoid::regproc::oid
        left join pg_catalog.pg_operator op on op.oid = a.aggsortop
    where 
        n.nspname = any(_schemas) and p.prokind = 'a'
) sub
$$;
/* #endregion _aggregates */

/* #region _ranges */
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
/* #endregion _ranges */

/* #region _routines */
create function schema._routines(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    specific_name text,
    comment text,
    definition text
)
language sql
as
$$
select
    r.type,
    r.schema,
    r.name, 
    r.specific_name, 
    r.comment,
    concat(
        'CREATE ',
        r.routine_type,
        ' ',
        r.signature, E'\n',
        'RETURNS ', r.returns, E'\n',
        'LANGUAGE ', lower(r.language), E'\n',
        case when r.security_type <> 'INVOKER' then 'SECURITY ' || r.security_type || E'\n' else '' end,
        case when r.is_deterministic = 'YES' then E'IMMUTABLE\n' else '' end,
        case when r.parallel_option = 'u' then '' 
            when r.parallel_option = 's' then E'PARALLEL SAFE\n' 
            when r.parallel_option = 'r' then E'PARALLEL RESTRICTED\n' 
        else '' end,
        case when r.cost_num = 100 then '' else 'COST ' || r.cost_num::text || E'\n' end,
        case when r.rows_num = 1000 or r.rows_num = 0  then '' else 'ROWS ' || r.rows_num::text || E'\n' end,
        case when r.is_strict then E'STRICT\n' else '' end,
        E'AS', E'\n',
        schema._parse_routine_body(r.routine_definition, r.type || ' ' || r.name, r.comment),
        E'\n'
    ) as definition
from (
    select
        r.routine_type,
        lower(r.routine_type) as type,
        quote_ident(r.specific_schema::text) as schema,
        concat(
            quote_ident(r.routine_name), 
            '(',
            array_to_string(array_agg((p.udt_schema || '.' || p.udt_name)::regtype::text order by p.ordinal_position), ', '), 
            ')'
        ) as name,
        r.specific_name,
        concat(
            schema._ident(r.specific_schema, r.routine_name),
            '(', 
            string_agg(
                E'\n    ' || 
                case when p.parameter_name is null then '' else quote_ident(p.parameter_name) end || 
                ' ' || 
                (p.udt_schema || '.' || p.udt_name)::regtype::text ||
                case when p.parameter_default is not null then ' = ' || p.parameter_default else '' end,
                ', ' order by p.ordinal_position
            ), 
            E'\n)'
        ) as signature,
        pgdesc.description as comment,
        lower(r.external_language) as language,
        r.security_type,
        r.is_deterministic,
        schema._parse_return(proc.oid, r.specific_schema, r.specific_name) as returns,
        r.routine_definition,
        proc.proisstrict as is_strict,
        procost as cost_num,
        prorows as rows_num,
        proparallel as parallel_option
    from
        information_schema.routines r
        join pg_catalog.pg_proc proc 
            on r.specific_name = proc.proname || '_' || proc.oid
        left join information_schema.parameters p 
            on r.specific_name = p.specific_name and r.specific_schema = p.specific_schema and (p.parameter_mode = 'IN' or p.parameter_mode = 'INOUT')
        left join pg_catalog.pg_description pgdesc 
            on proc.oid = pgdesc.objoid
    where
        r.specific_schema = any(_schemas)
        and proc.prokind in ('f', 'p')
        and not lower(r.external_language) = any(array['c', 'internal'])
    group by
        r.specific_schema, r.specific_name, r.routine_type, r.external_language, r.routine_name, 
        r.data_type, r.type_udt_catalog, r.type_udt_schema, r.type_udt_name,
        pgdesc.description, proc.proretset, r.routine_definition, proc.oid, r.security_type, r.is_deterministic
) r
order by 
    type desc, name
$$;
/* #endregion _routines */

/* #region _routines_order */
create function schema._routines_order(_schemas text[])
returns table (
    specific_schema text,
    specific_name text,
    order_by numeric
)
language sql
as
$$
with recursive cte as (
    select 
        r.specific_schema,
        r.specific_name,
        r.external_language,
        u.routine_schema,
        u.routine_name, 
        1::numeric - (case when r.external_language = 'SQL' then 0 else 0.5 end) as order_by
    from
        information_schema.routines r
        left join information_schema.routine_routine_usage u using (specific_schema, specific_name)
    where 
        u.routine_schema is null and r.specific_schema = any(_schemas)

    union all 

    select 
        r.specific_schema,
        r.specific_name,
        r.external_language,
        u.routine_schema,
        u.routine_name, 
        cte.order_by + 1 - (case when r.external_language = 'SQL' then 0 else 0.5 end) as order_by
    from
        information_schema.routines r
        join information_schema.routine_routine_usage u 
        on r.specific_schema = u.specific_schema and r.specific_name = u.specific_name
        join cte 
        on u.routine_schema = cte.specific_schema and u.routine_name = cte.specific_name
    where 
        r.specific_schema = any(_schemas)
)
select
    cte.specific_schema,
    cte.specific_name,
    cte.order_by
from cte
$$;
/* #endregion _routines_order */

/* #region _constraints */
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
                replace(
            case when position('.' in conrelid::regclass::text) > 0 
                then split_part(conrelid::regclass::text, '.', 2) 
                else conrelid::regclass::text
            end, '"', ''
        ) as table_name, 
        pg_get_constraintdef(oid, true) as definition
    from 
        pg_catalog.pg_constraint 
    where 
        connamespace::regnamespace::text = any(_schemas)
) sub
$$;
/* #endregion _constraints */

/* #region _indexes */
create function schema._indexes(_schemas text[])
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
    case when position(' UNIQUE ' in indexdef) > 0 then 'unique ' else ''end ||
    split_part(split_part(indexdef, 'USING ', 2), ' ', 1) || ' ' ||
    'index' as type,
    i.schemaname::text as schema,
    i.indexname::text as name, 
    i.schemaname::text as table_schema,
    i.tablename::text as table_name, 
    null::text as comment,
    indexdef || ';' as definition
from 
    pg_indexes i
where 
    i.schemaname = any(_schemas)
$$;
/* #endregion _indexes */

/* #region _triggers */
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
/* #endregion _triggers */

/* #region _policies */
create function schema._policies(_schemas text[])
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
    'policy' as type,
    p.schema,
    p.name, 
    p.schema as table_schema,
    p.table_name, 
    null::text as comment,
    concat(
        'CREATE POLICY ',
        quote_ident(p.name),
        ' ON ',
        quote_ident(p.schema), '.', quote_ident(p.table_name),
        ' AS ',
        permissive,
        ' FOR ',
        for_cmd,
        ' TO ',
        roles,
        ' ', using_exp, ' (',
        exp, ');'
    ) as definition
from (
    select
        n.nspname::text as schema,
        pol.polname::text as name, 
        c.relname::text as table_name, 
        case when pol.polpermissive then 'PERMISSIVE'::text else 'RESTRICTIVE'::text end as permissive,
        case when pol.polroles = '{0}'::oid[] then 'public' else (
            select string_agg(pg_authid.rolname, ', ')
            from pg_authid
            where pg_authid.oid = any(pol.polroles)
        )
        end as roles, 
        case pol.polcmd
            when 'r'::"char" then 'SELECT'
            when 'a'::"char" then 'INSERT'
            when 'w'::"char" then 'UPDATE'
            when 'd'::"char" then 'DELETE'
            when '*'::"char" then 'ALL'
        end::text as for_cmd,
        case when pol.polwithcheck is not null and pol.polqual is null then 'WITH CHECK' else 'USING' end as using_exp,
        case 
            when pol.polwithcheck is not null and pol.polqual is null 
            then pg_get_expr(pol.polwithcheck, pol.polrelid)
            else pg_get_expr(pol.polqual, pol.polrelid)
        end as exp
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    left join pg_namespace n on n.oid = c.relnamespace
    where 
        n.nspname = any(_schemas)
) p
$$;
/* #endregion _policies */

/* #region _columns */
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
/* #endregion _columns */

/* #region _tables_full */
create function schema._tables_full(_schemas text[])
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
begin
    perform schema._create_table_temp_tables(
        _schemas => _schemas,
        _create_columns => not schema._temp_exists('_columns'),
        _create_constraints => not schema._temp_exists('_constraints'),
        _create_indexes => not schema._temp_exists('_indexes'),
        _create_triggers => not schema._temp_exists('_triggers'),
        _create_policies => not schema._temp_exists('_policies'),
        _create_sequences => not schema._temp_exists('_sequences')
    );
    return query
    select 
        'table' as type,
        t.table_schema::text as schema, 
        t.table_name::text as name,
        pgdesc.description as comment,
        concat(
            'CREATE TABLE ',
            schema._ident(t.table_schema, t.table_name),
            E' (\n',
            col.definition,
            case when con.definition is not null then E',\n' || con.definition else '' end,
            E'\n);',
            case when pgdesc.description is not null then E'\n\n' || concat(
                'COMMENT ON TABLE ',
                schema._ident(t.table_schema, t.table_name),
                ' IS ',
                schema._quote(pgdesc.description),
                ';'
            ) else '' end,
            case when col.comments is not null then case when con.definition is not null then E'\n' else E'\n\n' end || col.comments else '' end,
            case when idx.definition is not null then E'\n\n' || idx.definition else '' end,
            case when tr.definition is not null then E'\n\n' || tr.definition else '' end,
            case when pol.definition is not null then E'\n\n' || pol.definition else '' end,
            case when seq.definition is not null then E'\n\n' || seq.definition else '' end,
            E'\n'
        ) as definition
    from 
        information_schema.tables t
        join lateral (
            select 
                string_agg('    ' || l.short_definition, E',\n' order by order_by) as definition,
                string_agg(concat(
                    'COMMENT ON COLUMN ',
                    schema._ident(t.table_schema, t.table_name), '.', quote_ident(l.name),
                    ' IS ',
                    schema._quote(l.comment),
                    ';'
                ), E'\n' order by order_by) filter (where l.comment is not null) as comments
            from _columns l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) col on true

        left join lateral (
            select string_agg('    ' || l.short_definition, E',\n' order by l.order_by) as definition
            from _constraints l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) con on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _indexes l
            left join _constraints c using (name, table_schema, table_name)
            where 
                l.table_schema = t.table_schema 
                and l.table_name = t.table_name 
                and c.table_name is null
        ) idx on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _triggers l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) tr on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _policies l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) pol on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _sequences l
            where l.table_schema = t.table_schema and l.table_name = t.table_name and l.definition like 'ALTER %'
        ) seq on true

        left join pg_catalog.pg_stat_all_tables pgtbl
            on t.table_name = pgtbl.relname and t.table_schema = pgtbl.schemaname
        left join pg_catalog.pg_description pgdesc
            on pgtbl.relid = pgdesc.objoid and pgdesc.objsubid = 0
    where
        t.table_type = 'BASE TABLE'
        and t.table_schema = any(_schemas);
end;
$$;
/* #endregion _tables_full */

/* #region _tables */
create function schema._tables(_schemas text[])
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
begin
    perform schema._create_table_temp_tables(
        _schemas => _schemas,
        _create_columns => not schema._temp_exists('_columns'),
        _create_constraints => false,
        _create_indexes => false,
        _create_triggers => false,
        _create_policies => false,
        _create_sequences => false
    );
    return query
    select 
        'table' as type,
        t.table_schema::text as schema, 
        t.table_name::text as name,
        pgdesc.description as comment,
        concat(
            'CREATE TABLE ',
            schema._ident(t.table_schema, t.table_name),
            E' (\n',
            col.definition,
            E'\n);',
            case when pgdesc.description is not null then E'\n\n' || concat(
                'COMMENT ON TABLE ',
                schema._ident(t.table_schema, t.table_name),
                ' IS ',
                schema._quote(pgdesc.description),
                ';'
            ) else '' end,
            case when col.comments is not null then E'\n\n' || col.comments else '' end,
            E'\n'
        ) as definition
    from 
        information_schema.tables t
        join lateral (
            select 
                string_agg('    ' || l.short_definition, E',\n' order by order_by) as definition,
                string_agg(concat(
                    'COMMENT ON COLUMN ',
                    schema._ident(t.table_schema, t.table_name), '.', quote_ident(l.name),
                    ' IS ',
                    schema._quote(l.comment),
                    ';'
                ), E'\n' order by order_by) filter (where l.comment is not null) as comments
            from _columns l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) col on true
        left join pg_catalog.pg_stat_all_tables pgtbl
            on t.table_name = pgtbl.relname and t.table_schema = pgtbl.schemaname
        left join pg_catalog.pg_description pgdesc
            on pgtbl.relid = pgdesc.objoid and pgdesc.objsubid = 0
    where
        t.table_type = 'BASE TABLE'
        and t.table_schema = any(_schemas);
end;
$$;
/* #endregion _tables */

/* #region _views */
create function schema._views(_schemas text[])
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
            schema._quote(pgdesc.description),
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
/* #endregion _views */

/* #region _views_order */
create function schema._views_order(_schemas text[])
returns table (
    schema text,
    name text,
    order_by numeric
)
language sql
as
$$
with recursive view_usage_cte as (
    select view_schema, view_name, table_schema, table_name
    from information_schema.view_table_usage u
    join information_schema.views v using(table_schema, table_name)
    where view_schema = any(_schemas)
),
rec_cte as (
    select 
        v.table_schema as view_schema, 
        v.table_name as view_name,
        u.view_schema as table_schema, 
        u.view_name as table_name,
        1 as order_by
    from
        information_schema.views v
        left join view_usage_cte u on v.table_schema = u.view_schema and v.table_name = u.view_name
    where 
        u.view_schema is null and v.table_schema = any(_schemas)

    union all 

    select 
        u.view_schema, 
        u.view_name,
        u.table_schema, 
        u.table_name,
        c.order_by + 1 as order_by
    from
        view_usage_cte u
        join rec_cte c on u.table_schema = c.view_schema and u.table_name = c.view_name
    where 
        u.table_schema = any(_schemas)
)
select
    c.view_schema as schema, 
    c.view_name as name,
    c.order_by
from rec_cte c
$$;
/* #endregion _views_order */

/* #region _types */
create function schema._types(_schemas text[])
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
        'type' as type,
        n.nspname::text as schema,
        t.typname::text as name,
        pg_catalog.obj_description(t.oid, 'pg_type') as comment,
        concat(
            'CREATE TYPE ',
            schema._ident(n.nspname, t.typname),
            E' AS (\n',
            a.definition,
            E'\n);'
        ) as definition
    from 
        pg_catalog.pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        join pg_catalog.pg_class c on t.typrelid = c.oid and c.relkind = 'c'
        join lateral (
            select string_agg(
                concat(
                    '    ',
                    quote_ident(a.attname),
                    ' ',
                    pg_catalog.format_type(a.atttypid, a.atttypmod)
                ), E',\n' order by a.attnum
            ) as definition
            from pg_catalog.pg_attribute a
            where 
                a.attrelid = t.typrelid and a.attisdropped is false   
        ) a on true
    where 
        n.nspname = any(_schemas)
) sub;
$$;
/* #endregion _types */

/* #region _enums */
create function schema._enums(_schemas text[])
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
        'enum' as type,
        n.nspname::text as schema,
        t.typname::text as name,
        pg_catalog.obj_description(t.oid, 'pg_type') as comment,
        concat(
            'CREATE TYPE ',
            schema._ident(n.nspname, t.typname),
            E' AS ENUM (\n',
            e.definition,
            E'\n);'
        ) as definition
    from 
        pg_type t
        join pg_catalog.pg_namespace n on n.oid = t.typnamespace
        join lateral (
            select string_agg(
                concat(
                    '    ',
                    schema._quote(e.enumlabel)
                ), E',\n' order by e.enumsortorder
            ) as definition
            from pg_catalog.pg_enum e
            where 
                e.enumtypid = t.oid
        ) e on true
    where
        t.typtype = 'e' 
        and n.nspname = any(_schemas)
) sub;
$$;
/* #endregion _enums */

/* #region _domains */
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
/* #endregion _domains */

/* #region _rules */
create function schema._rules(_schemas text[])
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
    'rule' as type,
    r.schemaname::text as schema,
    r.rulename::text as name,
    null as comment,
    r.definition
from 
    pg_catalog.pg_rules r
where 
    schemaname = any(_schemas)
$$;
/* #endregion _rules */

/* #region _extensions */
create function schema._extensions()
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
    'extension' as type,
    null as schema,
    e.extname as name,
    a.comment,
    concat(
        'CREATE EXTENSION ',
        quote_ident(e.extname),
        ';'
    ) as definition
from 
    pg_extension e 
    join pg_available_extensions a on e.extname = a.name
where e.extname <> 'plpgsql'
$$;
/* #endregion _extensions */

/* #region _sequences */
create function schema._sequences(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    table_schema text,
    table_name text,
    column_name text,
    comment text,
    definition text
)
language sql
as
$$
select
    'sequence' as type,
    sub2.schema,
    sub2.name,
    sub2.table_schema,
    sub2.table_name,
    sub2.column_name,
    sub2.comment,
    unnest(array_remove(sub2.definition, null::text)) as definition
from (
    select
        sub1.schema,
        sub1.name,
        sub1.table_schema,
        sub1.table_name,
        sub1.column_name,
        sub1.comment,
        array[
            concat(
                'CREATE SEQUENCE ',
                sub1.sequence_name,
                ' START WITH ', sub1.start_value,
                ' INCREMENT BY ', sub1.increment_by,
                ' MINVALUE ', sub1.min_value,
                ' MAXVALUE ', sub1.max_value,
                ' CACHE ', sub1.cache_size,
                case when sub1.cycle then ' CYCLE;' else ' NO CYCLE;' end,
                case when sub1.comment is not null then
                    concat(
                        E'\n'
                        'COMMENT ON SEQUENCE ',
                        sub1.sequence_name,
                        ' IS ',
                        schema._quote(sub1.comment),
                        ';'
                    )
                    else ''
                end
            )::text,
            case when sub1.table_name is not null and sub1.column_name is not null and sub1.column_default is not null then
                concat(
                    'ALTER SEQUENCE ',
                    sub1.sequence_name,
                    ' OWNED BY ',
                    quote_ident(sub1.table_schema),
                    '.',
                    quote_ident(sub1.table_name),
                    '.',
                    quote_ident(sub1.column_name),
                    ';'
                )
                else null
            end::text
        ] as definition
    from (
        select
            cl.relnamespace::regnamespace::text as schema,
            cl.relname as name,
            cl.oid::regclass::text as sequence_name,
            dep.table_schema,
            dep.table_name,
            dep.column_name,
            col.column_default,
            pg_catalog.obj_description(seq.seqrelid) as comment,
            seq.seqstart as start_value,
            seq.seqmin as min_value,
            seq.seqmax as max_value,
            seq.seqincrement as increment_by,
            seq.seqcycle as cycle,
            seq.seqcache as cache_size
        from   
            pg_catalog.pg_class cl
            join pg_catalog.pg_sequence seq on seq.seqrelid = cl.relfilenode
            join information_schema.sequences is_seq 
            on cl.relnamespace::regnamespace::text = is_seq.sequence_schema and cl.relname = is_seq.sequence_name
            left join lateral (
                select
                    depcl.relnamespace::regnamespace::text as table_schema,
                    depcl.relname as table_name,
                    attrib.attname as column_name
                from pg_catalog.pg_depend dep
                join pg_catalog.pg_class depcl on dep.refobjid = depcl.relfilenode
                join pg_catalog.pg_attribute attrib on attrib.attnum = dep.refobjsubid and attrib.attrelid = dep.refobjid
                where dep.objid = seq.seqrelid and depcl.relnamespace::regnamespace::text = any(_schemas)
            ) dep on true
            left join information_schema.columns col
                on dep.table_schema = col.table_schema 
                and dep.table_name = col.table_name 
                and dep.column_name = col.column_name
                and position(cl.oid::regclass::text in col.column_default) > 0
        where cl.relnamespace::regnamespace::text = any(_schemas)
    ) sub1
) sub2
$$;
/* #endregion _sequences */

/* #region _temp_exists */
create function schema._temp_exists(text)
returns boolean
language sql
as 
$$
select exists(
    select 1 from information_schema.tables t
    where t.table_name = $1 and table_type = 'LOCAL TEMPORARY'
)
$$;
/* #endregion _temp_exists */

/* #region search */
create function schema.search(
    _schema text = null,
    _type text = null,
    _search text = null,
    _verbose boolean = true
)
returns table (
    type text,
    schema text,
    name text,
    comment text,
    definition text,
    table_schema text,
    table_name text
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

    if _verbose then
        raise notice 'Search schema: %', _schemas;
        raise notice 'Search type: %', _type;
        raise notice 'Search text: %', _search;
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
        t.definition,
        null as table_schema,
        null as table_name
    from schema._extensions() t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._types(_schemas) t
    where
        schema._search_filter(t, _type, _search);
        
    insert into pg_temp.search
    select 
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._enums(_schemas) t
    where
        schema._search_filter(t, _type, _search);

    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._ranges(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
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
        t.definition,
        null as table_schema,
        null as table_name
    from schema._tables_full(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select 
        sub.type,
        sub.schema,
        sub.name,
        sub.comment,
        sub.definition,
        sub.table_schema,
        sub.table_name
    from (
        select
            t.type, 
            t.schema, 
            t.table_name || '.' || quote_ident(t.name) as name, 
            t.comment,
            t.definition,
            t.table_schema,
            t.table_name
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
        t.definition,
        t.table_schema,
        t.table_name
    from _constraints t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition,
        t.table_schema,
        t.table_name
    from _indexes t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition,
        t.table_schema,
        t.table_name
    from _triggers t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select
        t.type, 
        t.schema, 
        t.name, 
        t.comment,
        t.definition,
        t.table_schema,
        t.table_name
    from _policies t
    where
        schema._search_filter(t, _type, _search);

    insert into pg_temp.search
    select 
        sub.type,
        sub.schema,
        sub.name,
        sub.comment,
        sub.definition,
        sub.table_schema,
        sub.table_name
    from (
        select 
            t.type,
            t.schema,
            t.name,
            t.comment,
            string_agg(t.definition, E'\n') as definition,
            t.table_schema,
            t.table_name
        from _sequences t
        group by
            t.type,
            t.schema,
            t.name,
            t.comment,
            t.table_schema,
            t.table_name
    ) sub
    where
        schema._search_filter(sub, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._views(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._routines(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._rules(_schemas) t
    where
        schema._search_filter(t, _type, _search);

    insert into pg_temp.search
    select  
        t.type,
        t.schema,
        t.name,
        t.comment,
        t.definition,
        null as table_schema,
        null as table_name
    from schema._aggregates(_schemas) t
    where
        schema._search_filter(t, _type, _search);
    
    return query
    select 
        r.type, r.schema, r.name, r.comment, r.definition, r.table_schema, r.table_name
    from pg_temp.search r
    order by 
        r.schema, r.type desc, r.name;
end;
$$;

comment on function schema.search(text, text, text, boolean) is 'Search and retrieve the schema objects in the database.';
/* #endregion search */

/* #region dump */
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
    _include_ranges boolean = true,
    _include_domains boolean = true,
    
    _include_tables boolean = true,
    _include_sequences boolean = true,
    _include_constraints boolean = true,
    _include_indexes boolean = true,

    _include_triggers boolean = true,
    _include_policies boolean = true,
    
    _include_views boolean = true,
    _include_routines boolean = true,
    _include_aggregates boolean = true,
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
        raise exception 'No schema found for expression: %', _schema;
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

    if _include_ranges then
        create temp table ranges_tmp on commit drop as
        select t.definition from schema._ranges(_schemas) t where schema._search_filter(t, _type, _search) order by t.schema, t.name;
        
        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- ranges');
            perform pg_temp.lines(definition) from ranges_tmp;
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
    end if;

    if _include_routines then
        create temp table routines_tmp on commit drop as
        select t.type, t.definition 
        from schema._routines(_schemas) t 
        left join schema._routines_order(_schemas) o 
        on t.schema = o.specific_schema and t.specific_name = o.specific_name
        where schema._search_filter(t, null, null) 
        order by o.order_by, t.schema, t.name;

        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- ' || (select string_agg(distinct type || 's', ', ') from routines_tmp));
            perform pg_temp.lines(definition) from routines_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_aggregates then
        create temp table aggregates_tmp on commit drop as
        select t.type, t.definition 
        from schema._aggregates(_schemas) t 
        where schema._search_filter(t, _type, _search) 
        order by t.schema, t.name;

        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- aggregates');
            perform pg_temp.lines(definition) from aggregates_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_views then
        create temp table views_tmp on commit drop as
        select t.type, t.definition 
        from schema._views(_schemas) t 
        left join schema._views_order(_schemas) o using (schema, name)
        where schema._search_filter(t, _type, _search) 
        order by o.order_by, t.schema, t.name;

        get diagnostics _count = row_count;
        if _count > 0 then
            perform pg_temp.lines('-- ' || (select string_agg(distinct type || 's', ', ') from views_tmp));
            perform pg_temp.lines(definition) from views_tmp;
            perform pg_temp.lines('');
        end if;
    end if;

    if _include_tables then
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

comment on function schema.dump(text, text, text, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) is 'Creates schema script dump.';
/* #endregion dump */

raise notice 'Schema "schema" functions installed.';

raise info 'Following public functions are available:';
for _t in (select concat(type, ' ', schema, '.', name) from schema.search('schema', 'function') where name not like '\_%') loop
    raise info '%', _t;
end loop;

end;
$install$;
