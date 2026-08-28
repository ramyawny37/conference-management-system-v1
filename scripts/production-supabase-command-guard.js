const path=require('path');
const productionRef='mpezfbvcdfxpgflehuot';

function tokenize(command){
  if(Array.isArray(command)) return command.map(String);
  const tokens=[];
  const pattern=/"((?:\\.|[^"\\])*)"|'([^']*)'|([^\s]+)/g;
  let match;
  while((match=pattern.exec(String(command)))) tokens.push(match[1]??match[2]??match[3]);
  return tokens;
}

function executableIndex(tokens){
  for(let index=0;index<tokens.length;index++){
    const base=path.basename(tokens[index]).toLowerCase().replace(/\.cmd$/,'');
    if(base==='supabase') return index;
    if((base==='npx'||base==='pnpx')&&tokens[index+1]){
      const next=path.basename(tokens[index+1]).toLowerCase().replace(/\.cmd$/,'');
      if(next==='supabase') return index+1;
    }
  }
  return -1;
}

function isForbidden(command){
  const tokens=tokenize(command);
  if(tokens.some(token=>token.replace(/\\/g,'/').replace(/^\.\//,'').includes('supabase/migrations')))
    return true;
  const executable=executableIndex(tokens);
  if(executable<0) return false;
  const args=tokens.slice(executable+1).filter(token=>!token.startsWith('-')).map(token=>token.toLowerCase());
  return args.some((token,index)=>token==='db'&&args[index+1]==='push')
    ||args.some((token,index)=>token==='migration'&&args[index+1]==='up')
    ||args.some((token,index)=>token==='migration'&&args[index+1]==='repair');
}

function guard(command,target){
  if(target===productionRef&&isForbidden(command))
    throw new Error('PRODUCTION_BULK_MIGRATION_COMMAND_FORBIDDEN_USE_DEDICATED_RUNNER');
  return true;
}
if(require.main===module){
  try{guard(process.argv.slice(2).join(' '),process.env.SUPABASE_PROJECT_REF);}
  catch(error){console.error(error.message);process.exitCode=1;}
}
module.exports={guard,isForbidden,tokenize,productionRef};
