'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {generate,databaseURL}=require('../files/bootstrap.cjs');
const input={POSTGRES_HOST:'db.internal',POSTGRES_PORT:'5432',POSTGRES_DB:'postgres',POSTGRES_PASSWORD:'p@ss:/?#[]&+=% word',JWT_SECRET:'j'.repeat(64),SIGNING_SEED:'s'.repeat(64),DASHBOARD_USERNAME:'supabase',DASHBOARD_PASSWORD:'d'.repeat(32),SUPABASE_PUBLISHABLE_KEY:'sb_publishable_'+'a'.repeat(40),SUPABASE_SECRET_KEY:'sb_secret_'+'b'.repeat(40),SECRET_KEY_BASE:'c'.repeat(64),REALTIME_DB_ENC_KEY:'e'.repeat(16),PG_META_CRYPTO_KEY:'f'.repeat(32)};
function verify(token,key,asymmetric){
 const [head,payload,signature]=token.split('.');const data=Buffer.from(head+'.'+payload);
 assert.ok(asymmetric?crypto.verify('sha256',data,{key:crypto.createPublicKey({key,format:'jwk'}),dsaEncoding:'ieee-p1363'},Buffer.from(signature,'base64url')):crypto.timingSafeEqual(crypto.createHmac('sha256',key).update(data).digest(),Buffer.from(signature,'base64url')));
 return JSON.parse(Buffer.from(payload,'base64url'));
}
test('legacy and asymmetric credentials verify with the same bundle',()=>{
 const b=generate(input),keys=JSON.parse(b.JWT_JWKS).keys;
 assert.equal(verify(b.ANON_KEY,input.JWT_SECRET,false).role,'anon');
 assert.equal(verify(b.SERVICE_ROLE_KEY,input.JWT_SECRET,false).role,'service_role');
 assert.equal(verify(b.ANON_KEY_ASYMMETRIC,keys[0],true).role,'anon');
 assert.equal(verify(b.SERVICE_ROLE_KEY_ASYMMETRIC,keys[0],true).role,'service_role');
 assert.equal(keys[0].d,undefined);assert.equal(keys[1].k,Buffer.from(input.JWT_SECRET).toString('base64url'));
 assert.equal(b.SIGNING_SEED,undefined);
});
test('restart preserves signing keys, public API keys and legacy JWTs',()=>{
 const a=generate(input),b=generate(input);
 for(const key of ['JWT_KEYS','JWT_JWKS','SUPABASE_PUBLISHABLE_KEY','SUPABASE_SECRET_KEY','ANON_KEY','SERVICE_ROLE_KEY'])assert.equal(a[key],b[key]);
});
test('API key rotation preserves session verification keys',()=>{
 const a=generate(input),b=generate({...input,SUPABASE_SECRET_KEY:'sb_secret_'+'z'.repeat(40)});
 assert.equal(a.JWT_JWKS,b.JWT_JWKS);assert.notEqual(a.SUPABASE_SECRET_KEY,b.SUPABASE_SECRET_KEY);
});
test('seed rotation changes signing keys while preserving legacy verification',()=>{
 const a=generate(input),b=generate({...input,SIGNING_SEED:'x'.repeat(64)});
 assert.notEqual(a.JWT_KEYS,b.JWT_KEYS);assert.equal(a.ANON_KEY,b.ANON_KEY);
});
test('database URI credentials and names are encoded without changing their values',()=>{
 const u=new URL(databaseURL({...input,POSTGRES_DB:'db /?x'},'user@domain'));
 assert.equal(decodeURIComponent(u.password),input.POSTGRES_PASSWORD);assert.equal(decodeURIComponent(u.username),'user@domain');assert.equal(decodeURIComponent(u.pathname),'/db /?x');
 assert.equal(new URL(databaseURL({...input,POSTGRES_HOST:'::1'},'postgres')).hostname,'[::1]');
});
test('invalid inputs fail before publication without disclosing their values',()=>{
 assert.throws(()=>generate({...input,JWT_SECRET:'private'}),/Invalid|invalid credential: JWT_SECRET/);
 assert.throws(()=>generate({...input,REALTIME_DB_ENC_KEY:'e'.repeat(17)}),/16 characters/);
 assert.throws(()=>generate({...input,POSTGRES_HOST:'db/evil'}),/Invalid database address/);
});
