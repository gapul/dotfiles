#!/usr/bin/env python3
"""Apple 端末用の設定プロファイル (.mobileconfig) を sops の値から組み立てる。

このファイル自体には秘密が無い。値は実行時に sops から取るので、リポジトリに置ける。
出力される .mobileconfig は平文の資格情報を含むので、**インストールしたら消すこと**。

  ./scripts/gen-apple-profile.py [出力先]

入るもの:
  - CalDAV / CardDAV (自宅の Radicale)
  - IMAP/SMTP (個人 / 学校 / 会社。3 つとも Google Workspace なのでサーバは共通)

パスワードは sops にある分だけ埋め込む。無いものは初回接続時に本人が入れる形になる。
Google は 2 段階認証を有効にしているとアプリパスワードでないと IMAP に入れない。
"""

import os
import plistlib
import subprocess
import sys
import uuid

DAV_HOST = "dav.gapul.net"
IMAP_HOST = "imap.gmail.com"
SMTP_HOST = "smtp.gmail.com"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/tmp/gapul.mobileconfig")


def sops(path):
    """sops から 1 つだけ取り出す。無ければ空文字。値は表示しない。"""
    r = subprocess.run(
        # secrets.yaml は common / darwin / homelab に分割済み。ここで要るのは
        # radicale と pii なので common。
        ["sops", "-d", "--extract", path, "secrets/common.yaml"],
        cwd=REPO, capture_output=True, text=True,
    )
    return r.stdout.strip() if r.returncode == 0 else ""


base = "net.gapul.apple"
content = []


def add(kind, ident, name, extra):
    p = {
        "PayloadType": kind,
        "PayloadVersion": 1,
        "PayloadIdentifier": f"{base}.{ident}",
        "PayloadUUID": str(uuid.uuid4()),
        "PayloadDisplayName": name,
    }
    p.update(extra)
    content.append(p)


dav_user = sops('["radicale"]["username"]') or "gapul"
dav_pw = sops('["radicale"]["password"]')

add("com.apple.caldav.account", "caldav", "Calendars and Tasks", {
    "CalDAVAccountDescription": "Radicale (gapul.net)",
    "CalDAVHostName": DAV_HOST, "CalDAVPort": 443, "CalDAVUseSSL": True,
    "CalDAVUsername": dav_user, "CalDAVPassword": dav_pw,
    "CalDAVPrincipalURL": f"/{dav_user}/",
})
add("com.apple.carddav.account", "carddav", "Contacts", {
    "CardDAVAccountDescription": "Radicale Contacts (gapul.net)",
    "CardDAVHostName": DAV_HOST, "CardDAVPort": 443, "CardDAVUseSSL": True,
    "CardDAVUsername": dav_user, "CardDAVPassword": dav_pw,
    "CardDAVPrincipalURL": f"/{dav_user}/",
})

MAILS = [
    ("mail-personal", "Personal Mail", "personal", "gmail_app_password_mail"),
    ("mail-school", "School Mail", "school", "gmail_app_password_school"),
    ("mail-work", "Work Mail", "work", "gmail_app_password_work"),
]

for ident, label, key, pw_key in MAILS:
    addr = sops(f'["pii"]["email_{key}"]')
    if not addr:
        continue
    payload = {
        "EmailAccountDescription": label,
        "EmailAccountName": dav_user,
        "EmailAccountType": "EmailTypeIMAP",
        "EmailAddress": addr,
        "IncomingMailServerHostName": IMAP_HOST,
        "IncomingMailServerPortNumber": 993,
        "IncomingMailServerUseSSL": True,
        "IncomingMailServerUsername": addr,
        "IncomingMailServerAuthentication": "EmailAuthPassword",
        "OutgoingMailServerHostName": SMTP_HOST,
        "OutgoingMailServerPortNumber": 587,
        "OutgoingMailServerUseSSL": True,
        "OutgoingMailServerUsername": addr,
        "OutgoingMailServerAuthentication": "EmailAuthPassword",
        "OutgoingPasswordSameAsIncomingPassword": True,
        "SMIMEEnabled": False,
    }
    pw = sops(f'["pii"]["{pw_key}"]')
    if pw:
        payload["IncomingPassword"] = pw
    add("com.apple.mail.managed", ident, label, payload)

profile = {
    "PayloadType": "Configuration",
    "PayloadVersion": 1,
    "PayloadIdentifier": base,
    "PayloadUUID": str(uuid.uuid4()),
    "PayloadDisplayName": "gapul (Radicale + Mail)",
    "PayloadDescription": "Self-hosted calendars, tasks, contacts and mail accounts",
    "PayloadOrganization": "gapul",
    "PayloadRemovalDisallowed": False,
    "PayloadContent": content,
}

with open(OUT, "wb") as f:
    plistlib.dump(profile, f)
os.chmod(OUT, 0o600)

print(f"作成: {OUT}")
for p in content:
    real = [k for k in p if k in ("CalDAVPassword", "CardDAVPassword", "IncomingPassword") and p[k]]
    print(f"  {p['PayloadDisplayName']:22} {'パスワード埋め込み' if real else 'パスワードは初回に入力'}")
print("\nこのファイルは平文の資格情報を含む。インストールしたら消すこと。")
