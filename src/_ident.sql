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