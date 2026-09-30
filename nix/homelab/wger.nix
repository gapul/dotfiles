# Meal logging (the groundwork for replacing Asken).
#
# Asken's core is "take a photo, it estimates the meal as Japanese food and gives a score", and no
# FOSS does that. Broken down, it is "food diary + food database" and "estimation from photos";
# the former can ride on existing software. wger can be self-hosted, has a REST API, and has an
# official iOS app. The latter can be added later as a thin layer (Shortcut → any model → this
# API).
#
# The official compose is 6 services: web + nginx + postgres + redis + celery + powersync, but
# only web runs here:
#   - The DB is SQLite (created in /home/wger/db unless DJANGO_DB_* is passed). There is a single
#     user, and meal records are small.
#   - Static files are served directly by Caddy instead of nginx (pre in hosts/homeserver.nix).
#     The container only runs gunicorn; /static and /media are read from disk.
#   - celery exists for async imports (ingredient sync from wger.de), but that is unnecessary
#     here since the plan is to load the 8th-edition food composition tables myself.
#     USE_CELERY=False.
#
# The ingredient database does not sync wger.de's default (derived from Open Food Facts). It has
# almost no Japanese fresh food or prepared dishes, so it would just be noise. Instead, MEXT's
# 8th-edition Standard Tables of Food Composition are ETL'd and pushed in via the API (reusing
# the asset decided on for mogura).
_:

let
  dataDir = "/var/lib/homelab/wger";
in
{
  systemd.tmpfiles.rules = [
    # The image runs as the wger user with uid/gid 1000.
    "d ${dataDir} 0755 1000 1000 -"
    "d ${dataDir}/db 0755 1000 1000 -"
    "d ${dataDir}/static 0755 1000 1000 -"
    "d ${dataDir}/media 0755 1000 1000 -"
  ];

  virtualisation.oci-containers.containers.wger = {
    image = "docker.io/wger/server:latest";
    # Only SECRET_KEY. Placed by sops (managedFiles in secrets.nix).
    environmentFiles = [ "/var/lib/secrets/wger.env" ];
    environment = {
      TZ = "Asia/Tokyo";
      TIME_ZONE = "Asia/Tokyo";
      SITE_URL = "https://food.gapul.net";
      CSRF_TRUSTED_ORIGINS = "https://food.gapul.net";
      ALLOW_REGISTRATION = "False";
      ALLOW_GUEST_USERS = "False";
      DJANGO_DEBUG = "False";
      # Without this it fails saying the environment variable is missing (there is no default). The
      # SQLite file lives in /home/wger/db (the image provides that directory).
      DJANGO_DB_ENGINE = "django.db.backends.sqlite3";
      DJANGO_DB_DATABASE = "/home/wger/db/database.sqlite";
      DJANGO_DB_USER = "";
      DJANGO_DB_PASSWORD = "";
      DJANGO_DB_HOST = "";
      # An empty string is cast to int and fails. SQLite never reads it, so any value works.
      DJANGO_DB_PORT = "5432";
      DJANGO_PERFORM_MIGRATIONS = "True";
      DJANGO_COLLECTSTATIC_ON_STARTUP = "True";
      # Caddy serves static files, so use the plain storage: neither S3 nor whitenoise.
      DJANGO_STORAGES_STATICFILES_BACKEND = "django.contrib.staticfiles.storage.StaticFilesStorage";
      USE_CELERY = "False";
      SYNC_EXERCISES_CELERY = "False";
      SYNC_INGREDIENTS_CELERY = "False";
      CACHE_API_EXERCISES_CELERY = "False";
      SYNC_EXERCISES_ON_STARTUP = "False";
    };
    volumes = [
      "${dataDir}/db:/home/wger/db:rw"
      "${dataDir}/static:/home/wger/static:rw"
      "${dataDir}/media:/home/wger/media:rw"
    ];
    ports = [ "127.0.0.1:8106:8000" ];
    log-driver = "journald";
  };
}
