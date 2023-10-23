create function schema.tables_full(_schemas text[] = schema._get_schema_array(null))
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
        _create_constraints => not schema.temp_exists('_constraints'),
        _create_indexes => not schema.temp_exists('_indexes'),
        _create_triggers => not schema.temp_exists('_triggers'),
        _create_policies => not schema.temp_exists('_policies'),
        _create_sequences => not schema.temp_exists('_sequences')
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
            case when con.definition is not null then E',\n' || con.definition else '' end,
            E'\n);',
            case when pgdesc.description is not null then E'\n\n' || concat(
                'COMMENT ON TABLE ',
                schema._ident(t.table_schema, t.table_name),
                ' IS ',
                schema.quote(pgdesc.description),
                ';'
            ) else '' end,
            case when col.comments is not null then case when con.definition is not null then E'\n' else E'\n\n' end || col.comments else '' end,
            case when idx.definition is not null then E'\n\n' || idx.definition else '' end,
            case when tr.definition is not null then E'\n\n' || tr.definition else '' end,
            case when pol.definition is not null then E'\n\n' || pol.definition else '' end,
            case when seq.definition is not null then E'\n\n' || seq.definition else '' end,
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

        left join lateral (
            select string_agg('    ' || l.short_definition, E',\n' order by l.order_by) as definition
            from _constraints l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) con on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _indexes l
            left join _constraints c using (name, table_schema, table_name)
            where 
                l.table_schema = t.table_schema 
                and l.table_name = t.table_name 
                and c.table_name is null
        ) idx on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _triggers l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) tr on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _policies l
            where l.table_schema = t.table_schema and l.table_name = t.table_name
        ) pol on true

        left join lateral (
            select string_agg(l.definition, E'\n') as definition
            from _sequences l
            where l.table_schema = t.table_schema and l.table_name = t.table_name and l.definition like 'ALTER %'
        ) seq on true

        left join pg_catalog.pg_stat_all_tables pgtbl
            on t.table_name = pgtbl.relname and t.table_schema = pgtbl.schemaname
        left join pg_catalog.pg_description pgdesc
            on pgtbl.relid = pgdesc.objoid and pgdesc.objsubid = 0
    where
        t.table_type = 'BASE TABLE'
        and t.table_schema = any(_schemas);
end;
$$;