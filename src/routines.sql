create function schema.routines(_schemas text[] = schema._get_schema_array(null))
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
        r.routine_definition
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
        and lower(r.external_language) = any(array['sql', 'plpgsql'])
    group by
        r.specific_schema, r.specific_name, r.routine_type, r.external_language, r.routine_name, 
        r.data_type, r.type_udt_catalog, r.type_udt_schema, r.type_udt_name,
        pgdesc.description, proc.proretset, r.routine_definition, proc.oid, r.security_type, r.is_deterministic
) r
order by type desc, name
$$;