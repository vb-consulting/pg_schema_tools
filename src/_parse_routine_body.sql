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