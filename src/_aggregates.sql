create function schema._aggregates(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    comment text,
    definition text
)
language sql
as
$$
select 
    sub.type,
    sub.schema,
    sub.name,
    sub.comment,
    concat(
        sub.definition,
        case when sub.comment is null then '' else
            concat(
                E'\n',
                'COMMENT ON AGGREGATE ',
                sub.signature,
                ' IS ',
                schema._quote(sub.comment),
                E';'
            )
        end
    )
from (
    select
        'aggregate' as type,
        n.nspname as schema,
        p.proname as name,
        pg_catalog.obj_description(p.oid, 'pg_proc') as comment,
        format('%I.%I(%s)', n.nspname, p.proname, format_type(a.aggtranstype, null)) as signature,
        format(
            E'CREATE AGGREGATE %I.%I(%s) (\n%s\n);',
            n.nspname,
            p.proname,
            format_type(a.aggtranstype, null),
            array_to_string(
                array[
                    format('    SFUNC = %s', a.aggtransfn::regproc),
                    format('    STYPE = %s', format_type(a.aggtranstype, NULL)),
                    case a.aggfinalfn when '-'::regproc then null else format('    FINALFUNC = %s', a.aggfinalfn::text) end,
                    case a.aggsortop when 0 then null else format('    SORTOP = %s', op.oprname) end,
                    case when a.agginitval is null then null else format('    INITCOND = %s', a.agginitval) end
                ], E',\n'
            )
        ) as definition
    from 
        pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on p.pronamespace = n.oid
        join pg_catalog.pg_aggregate a on p.oid = a.aggfnoid::regproc::oid
        left join pg_catalog.pg_operator op on op.oid = a.aggsortop
    where 
        n.nspname = any(_schemas) and p.prokind = 'a'
) sub
$$;
