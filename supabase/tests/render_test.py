#!/usr/bin/env python3
"""Exercise every Supabase workload and the credential/integration boundaries."""
import pathlib, subprocess, tempfile, unittest, yaml
CHART=pathlib.Path(__file__).resolve().parents[1]
def render(overrides=None):
 with tempfile.NamedTemporaryFile(mode='w',suffix='.yaml') as stream:
  yaml.safe_dump(overrides or {},stream);stream.flush()
  return [d for d in yaml.safe_load_all(subprocess.check_output(['helm','template','test',str(CHART),'-f',stream.name],text=True)) if d]
def workloads(docs):return {d['metadata']['labels']['app.kubernetes.io/component']:d for d in docs if d['kind']=='Deployment'}
def env(container):return {v['name']:v for v in container['env']}
class Render(unittest.TestCase):
 def test_names_selectors_and_pause(self):
  for replicas in [0,1]:
   docs=render({'replicaCount':replicas,'nameOverride':'custom','fullnameOverride':'custom-instance'})
   ws=workloads(docs);self.assertEqual(set(ws),{'gateway','auth','rest','realtime','storage','meta','studio'})
   for name,w in ws.items():
    self.assertEqual(w['spec']['replicas'],replicas)
    selector=w['spec']['selector']['matchLabels'];self.assertEqual(selector['app.kubernetes.io/name'],'custom')
    self.assertEqual(selector['app.kubernetes.io/component'],name)
    self.assertTrue(all(w['spec']['template']['metadata']['labels'][k]==v for k,v in selector.items()))
   self.assertEqual(len([d for d in docs if d['kind']=='Job']),replicas)
 def test_all_workload_controls(self):
  overrides={'imagePullSecrets':[{'name':'pull'}],'serviceAccount':{'name':'workload-identity','create':False},'components':{}}
  for name in workloads(render()):
   overrides['components'][name]={'minReadySeconds':0,'progressDeadlineSeconds':1,'terminationGracePeriodSeconds':0,'strategy':{'type':'Recreate','rollingUpdate':{'maxSurge':7}},'image':{'repository':'example/test','tag':'pin'},'env':[{'name':'CUSTOM','value':'test'}],'resources':{'requests':{'memory':'64Mi'}},'extraVolumes':[{'name':'custom','emptyDir':{}}],'extraVolumeMounts':[{'name':'custom','mountPath':'/custom'}]}
  for w in workloads(render(overrides)).values():
   spec=w['spec'];pod=spec['template']['spec'];main=pod['containers'][0]
   self.assertEqual(spec['strategy'],{'type':'Recreate'});self.assertEqual(spec['minReadySeconds'],0);self.assertEqual(spec['progressDeadlineSeconds'],1)
   self.assertEqual(pod['terminationGracePeriodSeconds'],0);self.assertEqual(pod['serviceAccountName'],'workload-identity');self.assertFalse(pod['automountServiceAccountToken'])
   self.assertEqual(pod['imagePullSecrets'],[{'name':'pull'}]);self.assertEqual(main['image'],'example/test:pin');self.assertEqual(env(main)['CUSTOM']['value'],'test')
   self.assertEqual(main['resources']['requests']['memory'],'64Mi');self.assertIn({'name':'custom','mountPath':'/custom'},main['volumeMounts'])
 def test_integrations_reach_only_their_consumers(self):
  secret=lambda k:{'name':k,'valueFrom':{'secretKeyRef':{'name':'external','key':k}}}
  docs=render({'integrationEnv':[{'name':'RELAY_HOST','value':'smtp.example.com'},secret('RELAY_PASSWORD'),secret('AWS_SECRET_ACCESS_KEY'),{'name':'AWS_ACCESS_KEY_ID','value':'access'},{'name':'STORAGE_BACKEND','value':'s3'}]})
  ws=workloads(docs)
  for name,w in ws.items():
   e=env(w['spec']['template']['spec']['containers'][0]);names=set(e)
   if name=='auth':self.assertEqual(e['GOTRUE_SMTP_PASS']['valueFrom']['secretKeyRef']['key'],'RELAY_PASSWORD')
   else:self.assertNotIn('GOTRUE_SMTP_PASS',names)
   if name=='storage':self.assertEqual(e['AWS_SECRET_ACCESS_KEY']['valueFrom']['secretKeyRef']['key'],'AWS_SECRET_ACCESS_KEY');self.assertEqual(e['STORAGE_BACKEND']['value'],'s3')
   else:self.assertNotIn('AWS_SECRET_ACCESS_KEY',names)
   self.assertNotIn('RELAY_PASSWORD',names)
 def test_bootstrap_least_privilege_and_gating(self):
  docs=render();role=next(d for d in docs if d['kind']=='Role')
  self.assertEqual(role['rules'],[{'apiGroups':[''],'resources':['secrets'],'resourceNames':['test-credentials'],'verbs':['patch']}])
  self.assertFalse(any(d['kind'].startswith('Cluster') for d in docs))
  for w in workloads(docs).values():
   pod=w['spec']['template']['spec'];self.assertEqual(pod['initContainers'][0]['name'],'credentials-ready')
   volume=next(v for v in pod['volumes'] if v['name']=='credentials-ready');self.assertEqual(volume['secret']['items'],[{'key':'ready','path':'ready'}])
 def test_storage_colocation_and_existing_claims(self):
  docs=render({'storage':{'persistence':{'existingClaim':'objects'}},'studio':{'persistence':{'existingClaim':'snippets'}}});ws=workloads(docs)
  self.assertFalse(any(d['kind']=='PersistentVolumeClaim' for d in docs))
  storage=ws['storage'];self.assertEqual(storage['spec']['strategy'],{'type':'Recreate'})
  pod=storage['spec']['template']['spec'];self.assertEqual([c['name'] for c in pod['containers']],['storage','imgproxy'])
  self.assertEqual(next(v for v in pod['volumes'] if v['name']=='data')['persistentVolumeClaim']['claimName'],'objects')
  self.assertEqual(env(pod['containers'][0])['IMGPROXY_URL']['value'],'http://127.0.0.1:5001')
 def test_env_override_no_duplicates(self):
  ws=workloads(render({'components':{'rest':{'env':[{'name':'PGRST_DB_SCHEMAS','value':'public'}]}}}))
  e=ws['rest']['spec']['template']['spec']['containers'][0]['env'];self.assertEqual(sum(v['name']=='PGRST_DB_SCHEMAS' for v in e),1)
if __name__=='__main__':unittest.main()
