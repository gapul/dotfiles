# Declarative first-run setup for Healthchecks, run through `healthchecks-manage shell`
# (homelab/healthchecks.nix). Idempotent: every object is get-or-created, so re-running on each
# activation only re-applies the values that come from sops/gatus.env.
#
# Why not click through the UI: the box redeploys itself from git, and a monitor whose checks and
# integrations live only in its database is the uptime-kuma shape that was dropped. What this
# creates is the owner account, one project with a fixed ping key (so jobs can ping by slug
# without a per-check UUID), the ntfy integration, and the checks listed in CHECKS.
import json
import os
from datetime import timedelta as td

from django.contrib.auth.models import User

from hc.accounts.models import Profile, Project
from hc.api.models import Channel, Check

email = os.environ["HC_ADMIN_EMAIL"]
password = os.environ["HC_ADMIN_PASSWORD"]
ping_key = os.environ["HC_PING_KEY"]
ntfy_url = os.environ.get("HC_NTFY_URL", "http://127.0.0.1:8082")
ntfy_topic = os.environ["NTFY_TOPIC"]
ntfy_token = os.environ["NTFY_TOKEN"]

# slug -> (period, grace, description). Jobs ping http://127.0.0.1:<port>/ping/<key>/<slug>.
CHECKS = {
    "duo-remind": (
        td(days=1),
        td(hours=3),
        "homelab/duo-remind.nix: 21:00 JST daily. Pings on success; /fail on error.",
    ),
}

user, created = User.objects.get_or_create(
    username=email, defaults={"email": email, "is_staff": True, "is_superuser": True}
)
if created or not user.check_password(password):
    user.set_password(password)
    user.is_staff = user.is_superuser = True
    user.save()
Profile.objects.for_user(user)

project, _ = Project.objects.get_or_create(owner=user, defaults={"name": "homeserver"})
if project.ping_key != ping_key:
    project.ping_key = ping_key
    project.save()

value = json.dumps(
    {"url": ntfy_url, "topic": ntfy_topic, "priority": 4, "priority_up": 3, "token": ntfy_token}
)
channel, _ = Channel.objects.get_or_create(project=project, kind="ntfy", defaults={"name": "ntfy"})
if channel.value != value:
    channel.value = value
    channel.save()

for slug, (timeout, grace, desc) in CHECKS.items():
    check, _ = Check.objects.get_or_create(
        project=project, slug=slug, defaults={"name": slug, "kind": "simple"}
    )
    changed = False
    for field, want in (("timeout", timeout), ("grace", grace), ("desc", desc), ("name", slug)):
        if getattr(check, field) != want:
            setattr(check, field, want)
            changed = True
    if changed:
        check.save()
    if not check.channel_set.filter(pk=channel.pk).exists():
        check.channel_set.add(channel)

print(f"healthchecks bootstrap: project={project.code} checks={Check.objects.filter(project=project).count()}")
