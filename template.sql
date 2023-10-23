do
$install$
begin

/* #region init */
if exists(select 1 as name from pg_namespace where nspname = '${this.schema}') then
    --drop schema ${this.schema} cascade;
    raise exception 'Schema "${this.schema}" already exists. Consider running "drop schema ${this.schema} cascade;" to recreate ${this.schema} schema.';
end if;

create schema schema;
/* #endregion init */

${this._prepare_params}

${this._get_schema_array}

${this._parse_column}

${this._parse_return}

${this._ident}

${this._parse_routine_body}

${this._create_table_temp_tables}

${this._search_filter}

${this._routines_order}

${this.quote}

${this.routines}

${this.constraints}

${this.indexes}

${this.triggers}

${this.policies}

${this.columns}

${this.tables_full}

${this.tables}

${this.views}

${this.types}

${this.enums}

${this.domains}

${this.rules}

${this.extensions}

${this.sequences}

${this.temp_exists}

${this.search}

${this.dump}

raise notice 'Schema "${this.schema}" functions installed.';

end;
$install$;
