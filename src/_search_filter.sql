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