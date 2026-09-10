#!/usr/bin/env python3
"""Exercise Supabase against a dedicated local kind cluster; never use a shared cluster."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time
import urllib.parse

import requests
import yaml

ROOT = Path(__file__).resolve().parents[2]


def command(args, *, text=None, timeout=900):
    """Capture operational output so generated credentials never enter test logs."""
    result = subprocess.run(args, input=text, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args[0]} {args[1]} failed: {result.stderr[-3000:]}')
    return result.stdout


class Acceptance:
    def __init__(self, args):
        self.args = args
        self.state = Path(args.state)
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.k = ['kubectl', '--kubeconfig', args.kubeconfig, '-n', args.namespace]
        config = json.loads(command(self.k + ['config', 'view', '--minify', '-o', 'json']))
        server = urllib.parse.urlparse(config['clusters'][0]['cluster']['server']).hostname
        if server not in ('127.0.0.1', 'localhost', '::1'):
            raise RuntimeError('Acceptance requires a dedicated local kind cluster')
        self.h = ['helm', '--kubeconfig', args.kubeconfig, '-n', args.namespace]
        self.port_forward = None
        self.base = ''

    def save(self, name, data):
        p = self.state / name
        p.write_text(json.dumps(data, indent=2))
        p.chmod(0o600)
        return str(p)

    def load(self, name):
        return json.loads((self.state / name).read_text())

    def apply(self, objects):
        command(self.k + ['apply', '-f', '-'], text=yaml.safe_dump_all(objects))

    def sql(self, query, database='postgres', pod='database-0'):
        return command(self.k + ['exec', '-i', pod, '--', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
                                  '-U', 'supabase_admin', '-d', database, '-At'], text=query)

    def upgrade(self, values):
        f = self.save('app-values.json', values)
        command(self.h + ['upgrade', '--install', 'supabase', str(ROOT / 'supabase'), '-f', f,
                         '--wait', '--timeout', '12m'])

    def credentials(self):
        s = json.loads(command(self.k + ['get', 'secret', 'supabase-credentials', '-o', 'json']))
        return {k: base64.b64decode(v).decode() for k, v in s['data'].items()}

    def setup(self):
        """Install a fresh database and chart with persistent generated source credentials."""
        namespaces = json.loads(command(self.k + ['get', 'namespaces', '-o', 'json']))['items']
        if any(n['metadata']['name'] == self.args.namespace for n in namespaces):
            raise RuntimeError('Setup requires a new acceptance namespace')
        self.apply([{'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': self.args.namespace}}])
        app = yaml.safe_load((ROOT / 'supabase/values.yaml').read_text())
        c = app['credentials']
        c.update(POSTGRES_HOST='database', POSTGRES_PASSWORD=secrets.token_hex(16),
                 JWT_SECRET=secrets.token_hex(32), SIGNING_SEED=secrets.token_hex(32),
                 DASHBOARD_PASSWORD=secrets.token_hex(16), SECRET_KEY_BASE=secrets.token_hex(32),
                 REALTIME_DB_ENC_KEY=secrets.token_hex(8), PG_META_CRYPTO_KEY=secrets.token_hex(16),
                 SUPABASE_PUBLISHABLE_KEY='sb_publishable_'+secrets.token_hex(20),
                 SUPABASE_SECRET_KEY='sb_secret_'+secrets.token_hex(20))
        app['config'].update(publicUrl='http://localhost:8000', siteUrl='http://localhost:8000',
                             emailAutoconfirm='true', smtpSenderEmail='acceptance@example.test')
        db = {'fullnameOverride': 'database', 'containerName': 'postgres',
              'image': {'repository': 'wodby/supabase-postgres', 'tag': '17-0.1.0'},
              'persistence': {'enabled': True, 'size': '2Gi', 'mountPath': '/var/lib/postgresql'},
              'containerPorts': [{'name': 'postgres', 'containerPort': 5432}],
              'service': {'ports': [{'name': 'postgres', 'port': 5432, 'targetPort': 'postgres'}]},
              'args': ['postgres', '-c', 'config_file=/etc/postgresql/postgresql.conf'],
              'startupProbe': {'tcpSocket': {'port': 'postgres'}, 'periodSeconds': 5, 'failureThreshold': 90},
              'readinessProbe': {'exec': {'command': ['supabase-ops', 'check-ready']}},
              'envVars': [{'name': k, 'value': v} for k, v in {
                  'POSTGRES_PASSWORD': c['POSTGRES_PASSWORD'], 'PGPASSWORD': c['POSTGRES_PASSWORD'],
                  'PGUSER': 'supabase_admin', 'PGDATABASE': 'postgres', 'PGHOST': '127.0.0.1',
                  'POSTGRES_DB': 'postgres', 'JWT_SECRET': c['JWT_SECRET']}.items()]}
        self.save('database-values.json', db)
        print('Installing the released database image', flush=True)
        command(self.h + ['upgrade', '--install', 'database', str(ROOT / 'stateful'),
                         '-f', str(self.state/'database-values.json'), '--wait', '--timeout', '12m'])
        print('Installing Supabase components', flush=True)
        self.upgrade(app)
        self.save('original-credentials.json', self.credentials())
        print('Fresh database and Supabase startup passed', flush=True)

    def connect(self):
        """Forward only the local test gateway and recover forwarding after rollouts."""
        if self.port_forward:
            self.port_forward.terminate()
            self.port_forward.wait()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        self.port_forward = subprocess.Popen(self.k + ['port-forward', 'service/supabase', f'{port}:8000'],
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.base = f'http://127.0.0.1:{port}'
        for _ in range(60):
            try:
                requests.get(self.base+'/auth/v1/health', timeout=2)
                return
            except requests.RequestException:
                time.sleep(1)
        raise RuntimeError('Gateway forwarding did not become ready')

    def api(self, method, path, *, token=None, key=None, body=None, data=None, expected=(200,), headers=None):
        c = self.credentials()
        h = {'apikey': key or c['SUPABASE_PUBLISHABLE_KEY']}
        if token:
            h['Authorization'] = 'Bearer '+token
        h.update(headers or {})
        r = requests.request(method, self.base+path, headers=h, json=body, data=data, timeout=40)
        if r.status_code not in expected:
            raise RuntimeError(f'{method} {path}: HTTP {r.status_code}; expected {expected}')
        return r

    def smoke(self):
        """Verify actual Auth sessions, REST authorization, private storage and Realtime changes."""
        self.connect()
        self.api('GET', '/auth/v1/health')
        self.api('GET', '/', expected=(401,))
        c = self.credentials()
        basic = base64.b64encode((c['DASHBOARD_USERNAME']+':'+c['DASHBOARD_PASSWORD']).encode()).decode()
        self.api('GET', '/', headers={'Authorization': 'Basic '+basic})
        users = []
        for _ in range(2):
            email='acceptance-'+secrets.token_hex(6)+'@example.test'
            password=secrets.token_hex(16)
            data=self.api('POST', '/auth/v1/signup', body={'email': email, 'password': password}).json()
            assert data.get('access_token') and data.get('user', {}).get('id')
            users.append({'email': email, 'password': password, 'id': data['user']['id'], 'token': data['access_token']})
        self.save('users.json', users)
        self.sql(f"""CREATE TABLE public.wodby_acceptance(id integer PRIMARY KEY, owner_id uuid NOT NULL, value text);
ALTER TABLE public.wodby_acceptance ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.wodby_acceptance TO anon;
GRANT ALL ON public.wodby_acceptance TO authenticated;
CREATE POLICY own_rows ON public.wodby_acceptance TO authenticated USING(owner_id=auth.uid()) WITH CHECK(owner_id=auth.uid());
INSERT INTO public.wodby_acceptance VALUES(1,'{users[0]['id']}','first'),(2,'{users[1]['id']}','second');
ALTER PUBLICATION supabase_realtime ADD TABLE public.wodby_acceptance;
NOTIFY pgrst, 'reload schema';
SELECT vault.create_secret('acceptance-vault-value','acceptance');
""")
        time.sleep(3)
        assert self.api('GET','/rest/v1/wodby_acceptance?select=*').json()==[]
        for i,u in enumerate(users):
            rows=self.api('GET','/rest/v1/wodby_acceptance?select=*',token=u['token']).json()
            assert len(rows)==1 and rows[0]['id']==i+1
        self.api('POST','/rest/v1/wodby_acceptance',token=users[0]['token'],
                 body={'id':99,'owner_id':users[1]['id'],'value':'forbidden'},expected=(403,))
        c=self.credentials()
        assert len(self.api('GET','/rest/v1/wodby_acceptance?select=*',key=c['SUPABASE_SECRET_KEY']).json())==2
        self.api('GET','/rest/v1/wodby_acceptance',key='invalid-key',expected=(401,403))
        self.api('POST','/storage/v1/bucket',key=c['SUPABASE_SECRET_KEY'],body={'id':'acceptance','name':'acceptance','public':False})
        self.sql("CREATE POLICY acceptance_files ON storage.objects FOR ALL TO authenticated USING(bucket_id='acceptance') WITH CHECK(bucket_id='acceptance');")
        self.api('POST','/storage/v1/object/acceptance/hello.txt',token=users[0]['token'],data=b'acceptance-object',headers={'Content-Type':'text/plain'})
        assert self.api('GET','/storage/v1/object/acceptance/hello.txt',token=users[0]['token']).content==b'acceptance-object'
        self.api('GET','/storage/v1/object/acceptance/hello.txt',expected=(400,401,403))
        command(['node',str(ROOT/'scripts/supabase/realtime.cjs')],text=json.dumps({
            'url':self.base,'key':c['SUPABASE_PUBLISHABLE_KEY'],'token':users[0]['token'],'owner':users[0]['id']}),timeout=90)
        print('Auth, REST/RLS, private file storage and Realtime passed',flush=True)

    def verify_retained(self, *, object_name='hello.txt', content=b'acceptance-object'):
        """Verify old sessions, password hashes, tenant policies, encrypted data and objects after recovery."""
        self.connect()
        users = self.load('users.json')
        for i, u in enumerate(users):
            rows = self.api('GET', '/rest/v1/wodby_acceptance?select=*&order=id', token=u['token']).json()
            assert rows and all(r['owner_id'] == u['id'] for r in rows)
            assert rows[0]['id'] == i + 1
            data = self.api('POST', '/auth/v1/token?grant_type=password',
                            body={'email': u['email'], 'password': u['password']}).json()
            assert data.get('access_token') and data['user']['id'] == u['id']
        assert self.api('GET', '/rest/v1/wodby_acceptance?select=*').json() == []
        assert self.api('GET', '/storage/v1/object/acceptance/'+object_name,
                        token=users[0]['token']).content == content
        app = self.load('app-values.json')
        db = app['credentials']['POSTGRES_HOST']
        assert self.sql("SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='acceptance';", pod=db+'-0').strip() == 'acceptance-vault-value'
        before = self.load('original-credentials.json')
        after = self.credentials()
        for key in ['JWT_KEYS', 'JWT_JWKS', 'ANON_KEY', 'SERVICE_ROLE_KEY', 'SUPABASE_PUBLISHABLE_KEY',
                    'SUPABASE_SECRET_KEY', 'SECRET_KEY_BASE', 'REALTIME_DB_ENC_KEY', 'PG_META_CRYPTO_KEY']:
            assert before[key] == after[key], f'{key} changed unexpectedly'

    def lifecycle(self):
        """Exercise the chart's pause/resume contract and a configuration-only Helm upgrade."""
        app = self.load('app-values.json')
        app['replicaCount'] = 0
        self.upgrade(app)
        deployments = json.loads(command(self.k + ['get', 'deployments', '-l', 'app.kubernetes.io/instance=supabase', '-o', 'json']))['items']
        assert len(deployments) == 7 and all(d['spec']['replicas'] == 0 for d in deployments)
        app['replicaCount'] = 1
        self.upgrade(app)
        self.verify_retained()
        app['config']['maxRows'] = '900'
        self.upgrade(app)
        self.verify_retained()
        print('Pause/resume and configuration upgrade preserve sessions, rows, keys and files', flush=True)

    def pvc(self, name):
        return {'apiVersion': 'v1', 'kind': 'PersistentVolumeClaim', 'metadata': {'name': name},
                'spec': {'accessModes': ['ReadWriteOnce'], 'resources': {'requests': {'storage': '2Gi'}}}}

    def fixture(self, name, args, mounts, env=None, image='wodby/supabase-postgres:17-0.1.0'):
        """Run a bounded helper against only this namespace's fixture volumes."""
        pod = {'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name}, 'spec': {
            'restartPolicy': 'Never', 'activeDeadlineSeconds': 600,
            'containers': [{'name': 'fixture', 'image': image, 'command': args,
                'env': [{'name': k, 'value': v} for k, v in (env or {}).items()],
                'volumeMounts': [{'name': f'v{i}', 'mountPath': m[1], 'readOnly': m[2]} for i, m in enumerate(mounts)]}],
            'volumes': [{'name': f'v{i}', 'persistentVolumeClaim': {'claimName': m[0]}} for i, m in enumerate(mounts)]}}
        self.apply([pod])
        for _ in range(300):
            status = json.loads(command(self.k + ['get', 'pod', name, '-o', 'json']))['status'].get('phase')
            if status == 'Succeeded':
                return
            if status == 'Failed':
                # Helper output has no passwords or tokens; database dumps stay on the private volume.
                log = command(self.k + ['logs', name])
                raise RuntimeError(f'{name} failed: {log[-3000:]}')
            time.sleep(2)
        raise RuntimeError(f'{name} did not finish')

    def recover(self, mode='file'):
        """Restore a native database bundle into a fresh volume and recover matching object bytes."""
        app = self.load('app-values.json')
        source = app['credentials']['POSTGRES_HOST']
        target = 'database-restored-'+mode
        backup = 'backup-'+mode
        objects = 'objects-restored-'+mode
        app['replicaCount'] = 0
        self.upgrade(app)
        command(self.k + ['wait', '--for=delete', 'pod', '-l', 'app.kubernetes.io/instance=supabase,app.kubernetes.io/component=storage', '--timeout=120s'])
        self.apply([self.pvc(backup), self.pvc(objects)])
        db_env = {'PGHOST': source, 'PGPORT': '5432', 'PGUSER': 'supabase_admin', 'PGDATABASE': 'postgres',
                  'PGPASSWORD': app['credentials']['POSTGRES_PASSWORD'], 'WODBY_BACKUP_FILE': '/backup/backup.tar.gz'}
        self.fixture('backup-'+mode, ['supabase-ops', 'backup'],
                     [('data-'+source+'-0', '/var/lib/postgresql', True), (backup, '/backup', False)], db_env)
        self.fixture('extract-'+mode, ['python3', '-c',
            "import tarfile; from pathlib import Path; Path('/backup/extracted').mkdir(); tarfile.open('/backup/backup.tar.gz').extractall('/backup/extracted',filter='data')"], [(backup, '/backup', False)])
        if mode == 'file':
            claim = app['storage']['persistence'].get('existingClaim') or 'supabase-storage'
            self.fixture('copy-objects-'+mode, ['sh', '-ec', 'tar -C /source -cf /backup/objects.tar .; tar -C /target -xf /backup/objects.tar'],
                         [(claim, '/source', True), (objects, '/target', False), (backup, '/backup', False)])
            app['storage']['persistence']['existingClaim'] = objects
        else:
            self.copy_s3('acceptance-source', 'acceptance-recovered')
            app['storage']['bucket'] = 'acceptance-recovered'
        db = self.load('database-values.json')
        password = secrets.token_hex(16)
        db['fullnameOverride'] = target
        for env in db['envVars']:
            if env['name'] in ('POSTGRES_PASSWORD', 'PGPASSWORD'): env['value'] = password
        db['envVars'].append({'name': 'SUPABASE_IMPORT_ON_INIT', 'value': '1'})
        db['extraVolumes'] = [{'name': 'import', 'persistentVolumeClaim': {'claimName': backup}}]
        db['extraVolumeMounts'] = [{'name': 'import', 'mountPath': '/wodby/import', 'subPath': 'extracted', 'readOnly': True}]
        f = self.save(target+'-values.json', db)
        command(self.h + ['upgrade', '--install', target, str(ROOT/'stateful'), '-f', f, '--wait', '--timeout', '12m'])
        app['credentials'].update(POSTGRES_HOST=target, POSTGRES_PASSWORD=password)
        app['replicaCount'] = 1
        self.upgrade(app)
        self.verify_retained(object_name='s3.txt' if mode == 's3' else 'hello.txt',
                             content=b's3-acceptance-object' if mode == 's3' else b'acceptance-object')
        users = self.load('users.json')
        command(['node', str(ROOT/'scripts/supabase/realtime.cjs')], text=json.dumps({
            'url': self.base, 'key': self.credentials()['SUPABASE_PUBLISHABLE_KEY'],
            'token': users[0]['token'], 'owner': users[0]['id'], 'id': 5 if mode == 's3' else 4}), timeout=90)
        print(f'Native database import and coordinated {mode} object recovery passed', flush=True)

    def copy_s3(self, source, target):
        c = self.load('s3.json')
        self.fixture('s3-copy', ['sh', '-ec',
            f'mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null; mc mb local/{target}; mc mirror local/{source} local/{target}'],
            [], c, 'quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z')

    def s3(self):
        """Exercise the S3 integration with a private local MinIO fixture and a separate recovery bucket."""
        c = {'MINIO_ROOT_USER': 'acceptance', 'MINIO_ROOT_PASSWORD': secrets.token_hex(16)}
        self.save('s3.json', c)
        self.apply([{'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': 'minio', 'labels': {'fixture': 'minio'}},
            'spec': {'containers': [{'name': 'minio', 'image': 'quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z',
                'args': ['server', '/data'], 'env': [{'name': k, 'value': v} for k, v in c.items()],
                'readinessProbe': {'httpGet': {'path': '/minio/health/ready', 'port': 9000}},
                'volumeMounts': [{'name': 'data', 'mountPath': '/data'}]}], 'volumes': [{'name': 'data', 'emptyDir': {}}]}},
            {'apiVersion': 'v1', 'kind': 'Service', 'metadata': {'name': 'minio'},
             'spec': {'selector': {'fixture': 'minio'}, 'ports': [{'port': 9000, 'targetPort': 9000}]}}])
        command(self.k + ['wait', '--for=condition=Ready', 'pod/minio', '--timeout=300s'])
        self.fixture('s3-bucket', ['sh', '-ec',
            'mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null; mc mb local/acceptance-source'],
            [], c, 'quay.io/minio/mc:RELEASE.2025-04-16T18-13-26Z')
        app = self.load('app-values.json')
        app['storage'].update(bucket='acceptance-source', s3Endpoint='http://minio:9000')
        app['integrationEnv'] = [{'name': k, 'value': v} for k, v in {
            'AWS_ACCESS_KEY_ID': c['MINIO_ROOT_USER'], 'AWS_SECRET_ACCESS_KEY': c['MINIO_ROOT_PASSWORD'],
            'REGION': 'us-east-1', 'STORAGE_BACKEND': 's3'}.items()]
        self.upgrade(app)
        self.connect()
        users = self.load('users.json')
        self.api('POST', '/storage/v1/object/acceptance/s3.txt', token=users[0]['token'],
                 data=b's3-acceptance-object', headers={'Content-Type': 'text/plain'})
        self.verify_retained(object_name='s3.txt', content=b's3-acceptance-object')
        self.recover('s3')

    def close(self):
        if self.port_forward:
            self.port_forward.terminate()
            self.port_forward.wait()


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser()
    parser.add_argument('--kubeconfig',required=True)
    parser.add_argument('--namespace',default='supabase-acceptance')
    parser.add_argument('--state',required=True)
    parser.add_argument('step',choices=['setup','smoke','lifecycle','recover','s3','all'])
    args=parser.parse_args()
    test=Acceptance(args)
    try:
        if args.step in ('setup','all'): test.setup()
        if args.step in ('smoke','all'): test.smoke()
        if args.step in ('lifecycle','all'): test.lifecycle()
        if args.step in ('recover','all'): test.recover()
        if args.step in ('s3','all'): test.s3()
    finally:
        test.close()


if __name__=='__main__':
    main()
