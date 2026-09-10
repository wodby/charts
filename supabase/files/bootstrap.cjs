'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const https = require('node:https');

// Derive a stable P-256 key from a persistent seed, retrying the vanishingly rare invalid scalar.
function signingKey(seed) {
  let scalar = crypto.createHash('sha256').update('supabase-es256-v1:' + seed).digest();
  const ecdh = crypto.createECDH('prime256v1');
  for (;;) {
    try { ecdh.setPrivateKey(scalar); break; }
    catch { scalar = crypto.createHash('sha256').update(scalar).digest(); }
  }
  const point = ecdh.getPublicKey();
  const kid = crypto.createHash('sha256').update(point).digest('hex').slice(0, 24);
  return { kty: 'EC', crv: 'P-256', x: point.subarray(1,33).toString('base64url'),
    y: point.subarray(33).toString('base64url'), d: scalar.toString('base64url'), kid, alg: 'ES256', use: 'sig' };
}

// API role tokens are long-lived credentials. Rotation replaces their source keys explicitly.
function jwt(role, key, asymmetric = false) {
  const header = asymmetric ? { alg: 'ES256', typ: 'JWT', kid: key.kid } : { alg: 'HS256', typ: 'JWT' };
  const payload = { role, iss: 'supabase', iat: 0, exp: 4102444800 };
  const body = [header, payload].map(v => Buffer.from(JSON.stringify(v)).toString('base64url')).join('.');
  const signature = asymmetric
    ? crypto.sign('sha256', Buffer.from(body), { key: crypto.createPrivateKey({key, format: 'jwk'}), dsaEncoding: 'ieee-p1363' })
    : crypto.createHmac('sha256', key).update(body).digest();
  return body + '.' + signature.toString('base64url');
}

function databaseURL(c, user) {
  if (!/^[a-zA-Z0-9.\-:\[\]]+$/.test(c.POSTGRES_HOST) || !/^\d+$/.test(c.POSTGRES_PORT)) throw new Error('Invalid database address');
  const host = c.POSTGRES_HOST.includes(':') && !c.POSTGRES_HOST.startsWith('[') ? '['+c.POSTGRES_HOST+']' : c.POSTGRES_HOST;
  return `postgresql://${encodeURIComponent(user)}:${encodeURIComponent(c.POSTGRES_PASSWORD)}@${host}:${c.POSTGRES_PORT}/${encodeURIComponent(c.POSTGRES_DB)}`;
}

// Build the entire bundle before publishing it, so consumers never observe a partial rotation.
function generate(c) {
  const minimum = {POSTGRES_PASSWORD: 16, JWT_SECRET: 32, SIGNING_SEED: 32, DASHBOARD_PASSWORD: 16,
    SUPABASE_PUBLISHABLE_KEY: 32, SUPABASE_SECRET_KEY: 32, SECRET_KEY_BASE: 64, REALTIME_DB_ENC_KEY: 16, PG_META_CRYPTO_KEY: 32};
  for (const [name, length] of Object.entries(minimum)) {
    if (typeof c[name] !== 'string' || c[name].length < length) throw new Error(`Missing or invalid credential: ${name}`);
  }
  if (c.REALTIME_DB_ENC_KEY.length !== 16) throw new Error('REALTIME_DB_ENC_KEY must be 16 characters');
  if (!/^[A-Za-z0-9_-]+$/.test(c.DASHBOARD_USERNAME)) throw new Error('Invalid Studio username');
  const privateJwk = signingKey(c.SIGNING_SEED);
  const {d, ...publicJwk} = privateJwk;
  const symmetric = {kty:'oct',k:Buffer.from(c.JWT_SECRET).toString('base64url'),alg:'HS256'};
  const result = {...c, JWT_KEYS:JSON.stringify([privateJwk,symmetric]), JWT_JWKS:JSON.stringify({keys:[publicJwk,symmetric]}),
    ANON_KEY:jwt('anon',c.JWT_SECRET), SERVICE_ROLE_KEY:jwt('service_role',c.JWT_SECRET),
    ANON_KEY_ASYMMETRIC:jwt('anon',privateJwk,true), SERVICE_ROLE_KEY_ASYMMETRIC:jwt('service_role',privateJwk,true),
    AUTH_DATABASE_URL:databaseURL(c,'supabase_auth_admin'), REST_DATABASE_URL:databaseURL(c,'authenticator'),
    STORAGE_DATABASE_URL:databaseURL(c,'supabase_storage_admin')};
  delete result.SIGNING_SEED;
  return result;
}

async function publish() {
  const c = JSON.parse(fs.readFileSync('/input/credentials.json','utf8'));
  const values = generate(c);
  values.ready = process.env.SOURCE_HASH;
  const data = Object.fromEntries(Object.entries(values).map(([k,v])=>[k,Buffer.from(String(v)).toString('base64')]));
  const ca = fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/ca.crt');
  const token = fs.readFileSync('/var/run/secrets/kubernetes.io/serviceaccount/token','utf8').trim();
  const path = '/api/v1/namespaces/'+encodeURIComponent(process.env.POD_NAMESPACE)+'/secrets/'+encodeURIComponent(process.env.SECRET_NAME);
  await new Promise((resolve,reject)=> {
    const request = https.request({hostname:process.env.KUBERNETES_SERVICE_HOST,port:process.env.KUBERNETES_SERVICE_PORT_HTTPS || 443,path,
      method:'PATCH',ca,headers:{Authorization:'Bearer '+token,'Content-Type':'application/merge-patch+json'},timeout:30000}, response=> {
      response.resume();response.on('end',()=>response.statusCode===200 ? resolve() : reject(new Error('Credential publication failed with HTTP '+response.statusCode)));
    });
    request.on('timeout',()=>request.destroy(new Error('Credential publication timed out')));
    request.on('error',reject);request.end(JSON.stringify({data}));
  });
  console.log('Supabase credentials prepared');
}
if (require.main === module) publish().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports = {generate,signingKey,jwt,databaseURL};
