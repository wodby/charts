'use strict';
const fs=require('node:fs');
const crypto=require('node:crypto');
// JSON string escaping is valid inside YAML double-quoted scalars and Lua strings.
const values={...process.env,DASHBOARD_BASIC_AUTH:process.env.DASHBOARD_USERNAME+':{SHA}'+crypto.createHash('sha1').update(process.env.DASHBOARD_PASSWORD).digest('base64')};
for(const name of ['envoy.yaml','cds.yaml','lds.template.yaml']) {
 const source=fs.readFileSync('/templates/'+name,'utf8');
 const rendered=source.replace(/\$\{([A-Z_]+)\}/g,(_,key)=>{
  if(values[key]===undefined)throw new Error('Missing gateway variable: '+key);
  return JSON.stringify(values[key]).slice(1,-1);
 });
 fs.writeFileSync('/etc/envoy/'+name.replace('.template',''),rendered,{mode:0o600});
}
