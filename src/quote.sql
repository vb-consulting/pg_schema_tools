create function schema.quote(text)
returns text
language sql
as 
$$
select case when position(E'\'' in $1) > 0 then 'E''' || replace($1, E'\'', '\''') || E'\'' else E'\'' || $1 || E'\'' end
$$;