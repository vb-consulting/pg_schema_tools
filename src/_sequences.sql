create function schema._sequences(_schemas text[])
returns table (
    type text,
    schema text,
    name text,
    table_schema text,
    table_name text,
    column_name text,
    comment text,
    definition text
)
language sql
as
$$
select
    'sequence' as type,
    sub2.schema,
    sub2.name,
    sub2.table_schema,
    sub2.table_name,
    sub2.column_name,
    sub2.comment,
    unnest(array_remove(sub2.definition, null::text)) as definition
from (
    select
        sub1.schema,
        sub1.name,
        sub1.table_schema,
        sub1.table_name,
        sub1.column_name,
        sub1.comment,
        array[
            concat(
                'CREATE SEQUENCE ',
                sub1.sequence_name,
                ' START WITH ', sub1.start_value,
                ' INCREMENT BY ', sub1.increment_by,
                ' MINVALUE ', sub1.min_value,
                ' MAXVALUE ', sub1.max_value,
                ' CACHE ', sub1.cache_size,
                case when sub1.cycle then ' CYCLE;' else ' NO CYCLE;' end,
                case when sub1.comment is not null then
                    concat(
                        E'\n'
                        'COMMENT ON SEQUENCE ',
                        sub1.sequence_name,
                        ' IS ',
                        schema._quote(sub1.comment),
                        ';'
                    )
                    else ''
                end
            )::text,
            case when sub1.table_name is not null and sub1.column_name is not null and sub1.column_default is not null then
                concat(
                    'ALTER SEQUENCE ',
                    sub1.sequence_name,
                    ' OWNED BY ',
                    quote_ident(sub1.table_schema),
                    '.',
                    quote_ident(sub1.table_name),
                    '.',
                    quote_ident(sub1.column_name),
                    ';'
                )
                else null
            end::text
        ] as definition
    from (
        select
            cl.relnamespace::regnamespace::text as schema,
            cl.relname as name,
            cl.oid::regclass::text as sequence_name,
            dep.table_schema,
            dep.table_name,
            dep.column_name,
            col.column_default,
            pg_catalog.obj_description(seq.seqrelid) as comment,
            seq.seqstart as start_value,
            seq.seqmin as min_value,
            seq.seqmax as max_value,
            seq.seqincrement as increment_by,
            seq.seqcycle as cycle,
            seq.seqcache as cache_size
        from   
            pg_catalog.pg_class cl
            join pg_catalog.pg_sequence seq on seq.seqrelid = cl.relfilenode
            join information_schema.sequences is_seq 
            on cl.relnamespace::regnamespace::text = is_seq.sequence_schema and cl.relname = is_seq.sequence_name
            left join lateral (
                select
                    depcl.relnamespace::regnamespace::text as table_schema,
                    depcl.relname as table_name,
                    attrib.attname as column_name
                from pg_catalog.pg_depend dep
                join pg_catalog.pg_class depcl on dep.refobjid = depcl.relfilenode
                join pg_catalog.pg_attribute attrib on attrib.attnum = dep.refobjsubid and attrib.attrelid = dep.refobjid
                where dep.objid = seq.seqrelid and depcl.relnamespace::regnamespace::text = any(_schemas)
            ) dep on true
            left join information_schema.columns col
                on dep.table_schema = col.table_schema 
                and dep.table_name = col.table_name 
                and dep.column_name = col.column_name
                and position(cl.oid::regclass::text in col.column_default) > 0
        where cl.relnamespace::regnamespace::text = any(_schemas)
    ) sub1
) sub2
$$;