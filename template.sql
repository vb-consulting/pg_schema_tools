do
$install$
begin

/* #region init */
if exists(select 1 as name from pg_namespace where nspname = '${this.schema}') then
    drop schema ${this.schema} cascade;
    --raise exception 'Schema "${this.schema}" already exists. Consider running "drop schema ${this.schema} cascade;" to recreate ${this.schema} schema.';
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

${this._quote}

${this._routines}

${this._constraints}

${this._indexes}

${this._triggers}

${this._policies}

${this._columns}

${this._tables_full}

${this._tables}

${this._views}

${this._types}

${this._enums}

${this._domains}

${this._rules}

${this._extensions}

${this._sequences}

${this._temp_exists}

${this.search}

${this.dump}

raise notice 'Schema "${this.schema}" functions installed.';

end;
$install$;
