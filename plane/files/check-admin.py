# Refuses an unusable administrator before anything is installed. Run with "python" in /code before the migrations.
import os
import sys

from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from zxcvbn import zxcvbn

email = os.environ.get("PLANE_ADMIN_EMAIL", "").strip()
password = os.environ.get("PLANE_ADMIN_PASSWORD", "")
problems = []
try:
    validate_email(email)
except ValidationError:
    problems.append("PLANE_ADMIN_EMAIL is not an email address")
if not password:
    problems.append("PLANE_ADMIN_PASSWORD is empty")
elif not any(zxcvbn(w)["score"] >= 3 for w in {password[:128], password[-128:]}):
    problems.append("PLANE_ADMIN_PASSWORD is too weak for Plane; use a longer, less common password")
for problem in problems:
    print(f"[plane-setup] {problem}", file=sys.stderr, flush=True)
sys.exit(1 if problems else 0)
