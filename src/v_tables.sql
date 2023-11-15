create view schema.v_tables as
select 
    sub.table_oid,
    sub.schema_name,
    sub.table_name,
    coalesce(
        array_agg(pk_att.attname::text order by pk_att.attnum) filter (where pk_att.attname is not null), 
        array[]::text[]
    ) as pk_column_names,
    coalesce(
        array_agg(pk_att.atttypid::regtype::text order by pk_att.attnum) filter (where pk_att.attname is not null), 
        array[]::text[]
    ) as pk_column_types,
    coalesce(
        array_agg(fk_att.attname::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as fk_column_names,
    coalesce(
        array_agg(fk_att.atttypid::regtype::text order by pk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as fk_column_types,
    coalesce(
        array_agg(ref_cl.oid order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::oid[]
    ) as ref_table_oids,
    coalesce(
        array_agg(ref_cl.relnamespace::regnamespace::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_schema_names,
    coalesce(
        array_agg(ref_cl.relname::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_table_names,
    coalesce(
        array_agg(ref_att.attname::text order by fk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_column_names,
    coalesce(
        array_agg(ref_att.atttypid::regtype::text order by pk_att.attnum) filter (where fk_att.attname is not null), 
        array[]::text[]
    ) as ref_column_types
from (
        select 
            cl.oid as table_oid,
            cl.relnamespace::regnamespace::text as schema_name,
            cl.relname::text as table_name,
            con.contype,
            con.confrelid as fk_id,
            unnest(con.conkey) as column_attnum,
            unnest(con.confkey) as fk_column_attnum
        from 
            pg_catalog.pg_class cl
            left join pg_catalog.pg_constraint con on cl.oid = con.conrelid
        where
            cl.relnamespace::regnamespace::text not like 'pg_%' 
            and (con.contype = 'p' or con.contype = 'f')
    ) sub
    
    left join pg_attribute pk_att 
    on sub.table_oid = pk_att.attrelid and sub.column_attnum = pk_att.attnum and sub.contype = 'p'
        
    left join pg_attribute fk_att 
    on sub.table_oid = fk_att.attrelid and sub.column_attnum = fk_att.attnum and sub.contype = 'f'
    
    left join pg_class ref_cl on sub.fk_id = ref_cl.oid
    
    left join pg_attribute ref_att 
    on sub.fk_id = ref_att.attrelid and sub.fk_column_attnum = ref_att.attnum and sub.contype = 'f'

group by
    sub.table_oid,
    sub.schema_name,
    sub.table_name;