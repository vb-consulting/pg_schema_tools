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