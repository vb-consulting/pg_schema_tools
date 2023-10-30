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