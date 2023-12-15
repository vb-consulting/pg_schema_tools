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
            where p.specific_name = _specific_name and p.specific_schema = _specific_schema and p.parameter_mode = 'OUT'
        ) || E'\n)';
    end if;
    return _result;
end;
$$;