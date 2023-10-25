# pg_schema_tools

![License](https://img.shields.io/badge/license-MIT-green)
![GitHub Stars](https://img.shields.io/github/stars/vb-consulting/pg_schema_tools?style=social)
![GitHub Forks](https://img.shields.io/github/forks/vb-consulting/pg_schema_tools?style=social)

`pg_schema_tools` is a collection of tools and utilities for working with PostgreSQL database schemas implemented as set of Open-Source PostrgeSQL Functions.

## Features

Currently, there two public functions implemeneted:

1. `schema.search`
2. `schema.dump`

More functions is yet to come as this repository will be update in future.

### Function `schema.search`

Search and retrieve for the schema objects in database.

Signature: 

```
function schema.search(
    _schema text = null,
    _type text = null,
    _search text = null
)
returns table (
    type text,
    schema text,
    name text,
    comment text,
    definition text
)
```

- Parameters `_schema text = null, _type text = null, _search text = null` are used for searching (explained below).

- Default parameters search everything except system schemas: `select * from schema.search()`

- Function returns table with following columns:
  - `type text` - type of object (explained below).
  - `schema text` - schema
  - `name text` - name
  - `comment text` - comment on object
  - `definition text` - full DDL create statement for object

#### Object types

Object types can be either:

- `% index` - index types have name of index type in prefix, for example: `unique btree index`, `gist index`, `btree index`, etc
- `aggregate`
- `check` 
- `column`
- `domain`
- `enum`
- `foreign key`
- `function`
- `materialized view`
- `policy`
- `primary key`
- `procedure`
- `rule`
- `sequence`
- `table`
- `trigger`
- `type`
- `unique`
- `view`

#### Search parameters:

- `_schema text = null` - search schemas similar to this parameter or default (null) for all schemas except system schemas. See [`src/_get_schema_array.sql`](./src/_get_schema_array.sql) for more details.
- `_type text = null` - search types similar to this parameter or default (null) for all types. See above for a list of available types.
- `_search text = null` - search names, comments, and object definitions similar to this parameter or default (null) for all matches.

The search uses a **case insensitive** [`SIMILAR TO`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-SIMILARTO-REGEXP) operator for searching. 

This operator is a mix between `like` SQL pattern matching and regular expressions. 

Examples:

- `select * from schema.search('public')` - searches only schema named `public` (case insensitive)

- `select * from schema.search('public|my_schema')` - searches only schemas named `public` or `my_schema` (case insensitive)

- `select * from schema.search('public|my%')`- searches only schemas named `public` or schemas that start with `my` (case insensitive).

See [`SIMILAR TO`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-SIMILARTO-REGEXP) documentation or [`src/_search_filter.sql`](./src/_search_filter.sql) implemenation for more details.

### Function `schema.dump`

Creates schema script dump.

Signature:

```
CREATE FUNCTION schema.dump(
    _schema text = null, 
    _type text = null, 
    _search text = null, 
    _include_header boolean = true, 
    _include_transaction boolean = true, 
    _include_extensions boolean = true, 
    _include_schemas boolean = true, 
    _include_types boolean = true, 
    _include_enums boolean = true, 
    _include_domains boolean = true, 
    _include_tables boolean = true, 
    _include_sequences boolean = true, 
    _include_constraints boolean = true, 
    _include_indexes boolean = true, 
    _include_triggers boolean = true, 
    _include_policies boolean = true, 
    _include_views boolean = true, 
    _include_routines boolean = true, 
    _include_aggregates boolean = true, 
    _include_rules boolean = true, 
    _single_row boolean = false
)
RETURNS TABLE(line text)
```

- Parameters `_schema`, `_type`, and `_search` are standard search parameters explained above.
- Parameters that start with `_include_` are switches to include or exclude certain object types.
- Parameter `_single_row boolean = false` is a switch when set to true, will return script lines in a row (single column and single row); otherwise, multiple commands are returned in multiple rows.

## Limitations

1. These functions are tested to work on PostgreSQL 14, 15, and 16. Versions before 14 are not supported.

2. Generated DDL create scripts in this version do not include: 
   - Object owners.
   - User Privileges (Access Control List).
   - PostgreSQL Custom Range Types.
   - Some exotic custom aggregate options (most frequent ones are covered).

3. Schema dump scripts are not always guaranteed to get the precise order for creating interdependent views, functions, procedures, and aggregates. In this version, the current order is:
   1. routines (functions and procedures) ordered by interdependence within default parameter dependencies, SQL routines first.
   2. aggregates
   3. views ordered by dependency on other views.

Disclaimer: for 100 percent accurate and reliable schema dumps, please use the standard [`pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html) tool with `--schema-only` switch.

Schema scripts generated by these functions are intended to be used as helper tools in scripting, not as a complete `pg_dump` replacement.

## Installation

To use `pg_schema_tools`, you will need to have the following dependencies installed:

- PostgreSQL 14 or later

To install `pg_schema_tools`, execute [`/build.sql`](/build.sql) on your server, for example:

```bash
# 1. Clone the repostitory
# 2. Navigate to pg_schema_tools
# 3. Install this script on my localhost in database dvdrental using postgres user
$ git clone https://github.com/vb-consulting/pg_schema_tools.git
$ cd pg_schema_tools
$ psql --host=localhost --port=5432 --dbname=dvdrental --username=postgres --file=build.sql
```

### Troubleshooting

Install script will attempt to create a new schema called `schema`.

However, if that schema already exists, the script will return the following error:

```
psql:build.sql:2005: ERROR:  Schema "schema" already exists. Consider running "drop schema schema cascade;" to recreate schema schema.
CONTEXT:  PL/pgSQL function inline_code_block line 8 at RAISE
```

That means that you may already have that schema on your server, and the script will not attempt to drop it without permission. You have two choices:

1) Run `drop schema schema cascade;` and then rerun the install script.
2) Or edit `build.js` to target different schema names; run `node build.js` to create a new install script that targets different schema names.

## Contributing

If you would like to contribute to `pg_schema_tools`, please follow these guidelines:

1. Fork the repository
2. Make your changes
3. Submit a pull request

## License

`pg_schema_tools` is licensed under the MIT License. See [LICENSE](https://github.com/vb-consulting/pg_schema_tools/blob/master/LICENSE) for more information.
