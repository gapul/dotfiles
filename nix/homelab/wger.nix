# 食事の記録 (あすけんの置き換えの土台)。
#
# あすけんの中核は「写真を撮ると日本の食事として推定され、点数が出る」ことだが、
# それを満たす FOSS は無い。分解すると「食事日記 + 食品データベース」と「写真からの
# 推定」で、前者は既製品に乗れる。wger は自宅に置けて REST API があり、iOS アプリも
# 公式にある。後者は後から薄い層 (ショートカット → 好きなモデル → この API) として
# 足せる。
#
# 公式の compose は web + nginx + postgres + redis + celery + powersync の 6 つだが、
# ここでは web だけを動かす:
#   - DB は SQLite (DJANGO_DB_* を渡さなければ /home/wger/db に作られる)。使うのは
#     一人で、食事の記録はレコードが小さい。
#   - 静的ファイルは nginx ではなく Caddy が直接配る (hosts/homeserver.nix の pre)。
#     コンテナは gunicorn だけを持ち、/static と /media はディスクから読ませる。
#   - celery は非同期の取り込み (wger.de からの食材同期) のためにあるが、こちらは
#     八訂を自分で入れる前提なので要らない。USE_CELERY=False。
#
# 食材データベースは wger.de の既定 (Open Food Facts 由来) を同期しない。日本の
# 生鮮・惣菜がほとんど無く、ノイズになるため。文科省の八訂を ETL して API から
# 流し込む (mogura のために決めた資産をそのまま使う)。
{
  ...
}:

let
  dataDir = "/var/lib/homelab/wger";
in
{
  systemd.tmpfiles.rules = [
    # イメージは uid/gid 1000 の wger ユーザーで動く。
    "d ${dataDir} 0755 1000 1000 -"
    "d ${dataDir}/db 0755 1000 1000 -"
    "d ${dataDir}/static 0755 1000 1000 -"
    "d ${dataDir}/media 0755 1000 1000 -"
  ];

  virtualisation.oci-containers.containers.wger = {
    image = "docker.io/wger/server:latest";
    # SECRET_KEY だけ。sops が置く (secrets.nix の managedFiles)。
    environmentFiles = [ "/var/lib/secrets/wger.env" ];
    environment = {
      TZ = "Asia/Tokyo";
      TIME_ZONE = "Asia/Tokyo";
      SITE_URL = "https://food.gapul.net";
      CSRF_TRUSTED_ORIGINS = "https://food.gapul.net";
      ALLOW_REGISTRATION = "False";
      ALLOW_GUEST_USERS = "False";
      DJANGO_DEBUG = "False";
      DJANGO_PERFORM_MIGRATIONS = "True";
      DJANGO_COLLECTSTATIC_ON_STARTUP = "True";
      # 静的ファイルは Caddy が配るので、S3 でもなく whitenoise でもない素の置き場。
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
