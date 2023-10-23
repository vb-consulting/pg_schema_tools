create function schema.tables(_schemas text[] = schema._get_schema_array(null))
returns table (
    type text,
    schema text,
    name text,
    comment text,
    definition text
)
language plpgsql
as
$$
begin
    perform schema._create_table_temp_tables(
        _schemas => _schemas,
        _create_columns => not schema.temp_exists('_columns'),
        _create_constraints => false,
        _create_indexes => false,
        _create_triggers => false,
        _create_policies => false,
        _create_sequences => false
    );
    return query
    select 
        'table' as type,
        t.table_schema::text as schema, 
        t.table_name::text as name,
        pgdesc.description as comment,
        concat(
            'CREATE TABLE ',
            schema._ident(t.table_schema, t.table_name),
            E' (\n',
            col.definition,
            E'\n);',
            case when pgdesc.description is not null then E'\n\n' || concat(
                'COMMENT ON TABLE ',
                schema._ident(t.table_schema, t.table_name),
                ' IS ',
                schema.quote(pgdesc.description),
                ';'
            ) else '' end,
            case when col.comments is not null then E'\n\n' || col.comments else '' end,
            E'\n'
        ) as definition
    from 
        information_schema.tables t
        join lateral (
            select 
                string_agg('    ' || l.short_definition, E',\n' order by order_by) as definition,
                string_agg(concat(
                    'COMMENT ON COLUMN ',
                    schema._ident(t.table_schema, t.table_name), '.', quote_ident(l.name),
                    ' IS ',
                    schema.quote(l.comment),
                    ';'
                ), E'\n' order by order_by) filter (where l.comment is not null) as comments
            from _columns l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) col on true
        left join pg_catalog.pg_stat_all_tables pgtbl
            on t.table_name = pgtbl.relname and t.table_schema = pgtbl.schemaname
        left join pg_catalog.pg_description pgdesc
            on pgtbl.relid = pgdesc.objoid and pgdesc.objsubid = 0
    where
        t.table_type = 'BASE TABLE'
        and t.table_schema = any(_schemas);
end;
$$;