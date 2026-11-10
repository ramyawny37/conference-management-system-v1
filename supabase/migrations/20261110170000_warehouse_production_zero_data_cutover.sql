begin;

do $$
declare external_refs bigint;
begin
  select count(*) into external_refs
  from pg_constraint c
  join pg_namespace n on n.oid=c.connamespace
  where c.contype='f'
    and c.confrelid<>0
    and (select nn.nspname from pg_class cc join pg_namespace nn on nn.oid=cc.relnamespace where cc.oid=c.confrelid)='warehouse'
    and n.nspname<>'warehouse';
  if external_refs<>0 then
    raise exception 'WAREHOUSE_ZERO_DATA_EXTERNAL_DEPENDENCIES_FOUND' using errcode='55000';
  end if;
end $$;

truncate table
 warehouse.approval_records,
 warehouse.beneficiary_balances,
 warehouse.beneficiary_financial_entries,
 warehouse.reversal_requests,
 warehouse.adjustment_lines,
 warehouse.issue_lines,
 warehouse.receipt_lines,
 warehouse.transfer_lines,
 warehouse.stock_balances,
 warehouse.stock_movements,
 warehouse.adjustment_documents,
 warehouse.issue_documents,
 warehouse.receipt_documents,
 warehouse.transfer_documents,
 warehouse.document_registry,
 warehouse.party_roles,
 warehouse.parties,
 warehouse.item_units,
 warehouse.items,
 warehouse.categories,
 warehouse.units,
 warehouse.stores,
 warehouse.business_audit,
 warehouse.business_operations;

do $$
declare remaining bigint;
begin
 select coalesce(sum(row_count),0) into remaining
 from (
   select (xpath('/row/c/text()',query_to_xml(format('select count(*) c from warehouse.%I',c.relname),false,true,'')))[1]::text::bigint row_count
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='warehouse' and c.relkind='r'
 ) s;
 if remaining<>0 then
   raise exception 'WAREHOUSE_ZERO_DATA_GUARD_FAILED: % rows remain',remaining using errcode='55000';
 end if;
end $$;

commit;
