function checkedStdout(result,label){
  if(!result||result.error||result.status!==0){
    const detail=result&&(result.stderr||result.stdout)||result&&result.error&&result.error.message||'NO_RESULT';
    throw new Error(`EVIDENCE_COMMAND_FAILED_${label}: ${String(detail).trim()}`);
  }
  return String(result.stdout??'');
}

function parseJsonEvidence(raw,{label,expectedType,allowEmpty=true}){
  if(typeof raw!=='string'||raw.trim()==='') throw new Error(`EVIDENCE_EMPTY_OUTPUT_${label}`);
  let value;
  try{ value=JSON.parse(raw); }
  catch(error){ throw new Error(`EVIDENCE_MALFORMED_JSON_${label}: ${error.message}`); }
  const actualType=Array.isArray(value)?'array':value===null?'null':typeof value;
  if(actualType!==expectedType)
    throw new Error(`EVIDENCE_TYPE_MISMATCH_${label}: expected ${expectedType}, got ${actualType}`);
  if(!allowEmpty&&expectedType==='array'&&value.length===0)
    throw new Error(`EVIDENCE_EMPTY_SET_${label}`);
  return value;
}

module.exports={checkedStdout,parseJsonEvidence};
