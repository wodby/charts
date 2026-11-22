# Sets up Plane's first instance administrator, as Plane's own god-mode sign-up does, and closes that page.
# Run with "python manage.py shell" after the migrations, register_instance and configure_instance.
import os
import sys
import uuid

from django.contrib.auth.hashers import make_password
from django.db import transaction
from django.utils import timezone

from plane.db.models import Profile, User
from plane.license.models import Instance, InstanceAdmin


def say(message):
    print(f"[plane-setup] {message}", flush=True)


instance = Instance.objects.first()
if instance is None:
    say("Plane's instance is not registered")
    sys.exit(1)

if instance.is_setup_done or InstanceAdmin.objects.exists():
    say("The instance administrator is already set up")
    sys.exit(0)

email = os.environ.get("PLANE_ADMIN_EMAIL", "").strip().lower()
password = os.environ.get("PLANE_ADMIN_PASSWORD", "")
first_name = os.environ.get("PLANE_ADMIN_FIRST_NAME", "").strip() or "Admin"
instance_name = os.environ.get("PLANE_INSTANCE_NAME", "").strip()

with transaction.atomic():
    instance = Instance.objects.select_for_update().get(pk=instance.pk)
    user = User.objects.filter(email=email).first()
    if user is None:
        user = User.objects.create(
            first_name=first_name,
            email=email,
            username=uuid.uuid4().hex,
            password=make_password(password),
            is_password_autoset=False,
            is_active=True,
            token_updated_at=timezone.now(),
        )
        Profile.objects.create(user=user, company_name=instance_name)
    else:
        user.set_password(password)
        user.is_password_autoset = False
        user.is_active = True
        user.save()
    InstanceAdmin.objects.create(user=user, instance=instance)
    instance.is_setup_done = True
    if instance_name:
        instance.instance_name = instance_name
    instance.is_telemetry_enabled = False
    instance.save()

say(f"Set up the instance administrator {email}")
