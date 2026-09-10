'use strict';
const fs = require('node:fs');
const c = JSON.parse(fs.readFileSync(0, 'utf8'));
const url = c.url.replace('http:', 'ws:') + '/realtime/v1/websocket?apikey=' + encodeURIComponent(c.key) + '&vsn=1.0.0';
const ws = new WebSocket(url);
const timeout = setTimeout(() => { console.error('Realtime subscription/change timeout'); process.exit(1); }, 60000);
let inserted = false;
ws.onopen = () => ws.send(JSON.stringify({topic:'realtime:public:wodby_acceptance',event:'phx_join',ref:'1',payload:{
  config:{broadcast:{self:false},presence:{key:''},postgres_changes:[{event:'INSERT',schema:'public',table:'wodby_acceptance'}]},access_token:c.token
}}));
ws.onerror = () => { console.error('Realtime WebSocket failed'); process.exit(1); };
ws.onmessage = async event => {
  const message = JSON.parse(event.data);
  if (message.event === 'system' && message.payload.status === 'ok' && !inserted) {
    inserted = true;
    const response = await fetch(c.url + '/rest/v1/wodby_acceptance', {method:'POST', headers:{
      apikey:c.key,Authorization:'Bearer '+c.token,'Content-Type':'application/json'
    }, body:JSON.stringify({id:c.id || 3,owner_id:c.owner,value:'realtime-retained'})});
    if (!response.ok) { console.error('Realtime fixture insert failed: '+response.status); process.exit(1); }
  }
  if (message.event === 'postgres_changes' && message.payload.data?.record?.value === 'realtime-retained') {
    clearTimeout(timeout); ws.close(); console.log('Realtime authorized INSERT received');
  }
};
