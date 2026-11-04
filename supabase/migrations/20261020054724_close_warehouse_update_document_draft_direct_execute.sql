revoke all on function warehouse.update_document_draft(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function warehouse.update_document_draft(uuid, uuid, text, uuid, bigint, jsonb)
  to service_role;;
