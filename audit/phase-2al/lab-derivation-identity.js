function isApprovedLoopbackAddress(value){
  if(typeof value!=='string') return false;
  return value==='127.0.0.1'||value==='127.0.0.1/32'||value==='::1'||value==='::1/128';
}

function isApprovedLabDatabaseName(value){
  return typeof value==='string'&&/^phase2a[a-z0-9_]*$/i.test(value);
}

function normalizeUrlHostname(value){
  if(typeof value!=='string') return null;
  if(value.startsWith('[')&&value.endsWith(']')) return value.slice(1,-1);
  return value;
}

function isApprovedUrlHostname(value){
  return ['127.0.0.1','localhost','::1'].includes(normalizeUrlHostname(value));
}

function isApprovedLabUrl(value){
  if(typeof value!=='string'||/mpezfbvcdfxpgflehuot|gppwltrifgfxrkzvvxoe|supabase\.co/i.test(value))
    return false;
  try{return isApprovedUrlHostname(new URL(value).hostname);}
  catch(error){return false;}
}

const CANONICAL_BOOTSTRAP_ROLE='postgres';

function canonicalLabIdentityFailure(identity){
  if(!identity||identity.major!==17||!isApprovedLabDatabaseName(identity.database)
    ||!isApprovedLoopbackAddress(identity.address)) return 'IDENTITY';
  if(identity.currentUser!==CANONICAL_BOOTSTRAP_ROLE
    ||identity.sessionUser!==CANONICAL_BOOTSTRAP_ROLE
    ||identity.databaseOwner!==CANONICAL_BOOTSTRAP_ROLE)
    return 'NONCANONICAL_LAB_BOOTSTRAP_OWNER';
  return null;
}

module.exports={normalizeUrlHostname,isApprovedUrlHostname,isApprovedLoopbackAddress,
  isApprovedLabDatabaseName,isApprovedLabUrl,CANONICAL_BOOTSTRAP_ROLE,
  canonicalLabIdentityFailure};
