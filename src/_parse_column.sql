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