#!/bin/bash
# Installs or upgrades Plane's database before the background scheduler starts. The API, the workers and the live
# server wait until the migrations are applied, so nothing is served before the instance administrator is set up.
set -eo pipefail
cd /code
python manage.py wait_for_db
# Until an administrator exists, refuse settings Plane would not accept before anything is installed.
if ! python manage.py shell -c "import sys; from plane.license.models import InstanceAdmin; sys.exit(0 if InstanceAdmin.objects.exists() else 3)" >/dev/null 2>&1; then
  python /opt/wodby/check-admin.py
fi
python manage.py migrate --noinput
python manage.py register_instance "${HOSTNAME:-wodby}"
python manage.py configure_instance
python manage.py shell < /opt/wodby/setup.py
