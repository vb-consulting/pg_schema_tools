create function schema.policies(_schemas text[] = schema._get_schema_array(null))
returns table (
    type text,
    schema text,
    name text,
    table_schema text,
    table_name text,
    comment text,
    definition text
)
language sql
as
$$
select
    'policy' as type,
    p.schema,
    p.name, 
    p.schema as table_schema,
    p.table_name, 
    null::text as comment,
    concat(
        'CREATE POLICY ',
        quote_ident(p.name),
        ' ON ',
        quote_ident(p.schema), '.', quote_ident(p.table_name),
        ' AS ',
        permissive,
        ' FOR ',
        for_cmd,
        ' TO ',
        roles,
        ' ', using_exp, ' (',
        exp, ');'
    ) as definition
from (
    select
        n.nspname::text as schema,
        pol.polname::text as name, 
        c.relname::text as table_name, 
        case when pol.polpermissive then 'PERMISSIVE'::text else 'RESTRICTIVE'::text end as permissive,
        case when pol.polroles = '{0}'::oid[] then 'public' else (
            select string_agg(pg_authid.rolname, ', ')
            from pg_authid
            where pg_authid.oid = any(pol.polroles)
        )
        end as roles, 
        case pol.polcmd
            when 'r'::"char" then 'SELECT'
            when 'a'::"char" then 'INSERT'
            when 'w'::"char" then 'UPDATE'
            when 'd'::"char" then 'DELETE'
            when '*'::"char" then 'ALL'
        end::text as for_cmd,
        case when pol.polwithcheck is not null and pol.polqual is null then 'WITH CHECK' else 'USING' end as using_exp,
        case 
            when pol.polwithcheck is not null and pol.polqual is null 
            then pg_get_expr(pol.polwithcheck, pol.polrelid)
            else pg_get_expr(pol.polqual, pol.polrelid)
        end as exp
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    left join pg_namespace n on n.oid = c.relnamespace
    where 
        n.nspname = any(_schemas)
) p
$$;