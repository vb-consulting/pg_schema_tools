create function schema._quote(text)
returns text
language sql
immutable
as 
$$
select case when position(E'\'' in $1) > 0 then 'E''' || replace($1, E'\'', '\''') || E'\'' else E'\'' || $1 || E'\'' end
$$;