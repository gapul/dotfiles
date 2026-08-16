#!/usr/bin/env python3
"""MCP server over Notion's private API (token_v2): search, read, append, create.

Exists because Notion blocks guest accounts from the official MCP/API, so the
only way to reach workspaces we're a guest in is the same endpoint the web app
uses. Undocumented and can break without notice; if it starts 401ing, the
session cookie expired — re-run the extraction described in the memory note.

Credentials come from ~/.config/notion-private.env (mode 600), never argv/env
in the MCP config.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

BASE = "https://app.notion.com/api/v3"
ENV_FILE = os.path.expanduser("~/.config/notion-private.env")


def load_env():
    with open(ENV_FILE) as f:
        return dict(
            line.split("=", 1) for line in f.read().splitlines() if "=" in line
        )


ENV = load_env()
TOKEN = ENV["NOTION_TOKEN_V2"].strip()
USER_ID = ENV.get("NOTION_USER_ID", "").strip()


def api(endpoint, payload, user_id=None):
    """user_id picks which of the browser's logged-in Notion accounts to act as."""
    headers = {
        "Content-Type": "application/json",
        "Cookie": f"token_v2={TOKEN}",
        "User-Agent": "Mozilla/5.0",
    }
    if user_id:
        headers["x-notion-active-user-header"] = user_id
    req = urllib.request.Request(f"{BASE}/{endpoint}", data=json.dumps(payload).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def dashed(page_id):
    s = page_id.replace("-", "")
    return f"{s[:8]}-{s[8:12]}-{s[12:16]}-{s[16:20]}-{s[20:]}" if len(s) == 32 else page_id


def unwrap(record):
    """syncRecordValues nests one level deeper than loadPageChunk does."""
    v = record.get("value", {})
    return v.get("value", v)


def spaces():
    """[(space_id, name, user_id)] across every Notion account logged into the browser.

    getSpaces is keyed by user id, so a cookie holding several sessions lists them all.
    """
    out = []
    for user_id, blob in api("getSpaces", {}).items():
        names = {sid: unwrap(rec).get("name") for sid, rec in blob.get("space", {}).items()}
        for rec in blob.get("space_view", {}).values():
            sid = unwrap(rec).get("space_id")
            if sid:
                names.setdefault(sid, None)
        # a guest can't read the space record itself, so label those by the pages shared with us
        shared = {}
        for rec in api("loadUserContent", {}, user_id).get("recordMap", {}).get("block", {}).values():
            block = unwrap(rec)
            sid = block.get("space_id")
            if sid and not names.get(sid):
                shared.setdefault(sid, []).append(title_of(block))
        for sid, name in names.items():
            label = name or ("guest: " + ", ".join(shared[sid][:3]) if sid in shared else sid)
            out.append((sid, label, user_id))
    return out


def users():
    return list(api("getSpaces", {}).keys())


def rich_text(prop):
    return "".join(seg[0] for seg in (prop or []) if seg and seg[0] != "‣")


def title_of(block):
    props = block.get("properties") or {}
    return rich_text(props.get("title")) or "(untitled)"


PREFIX = {
    "header": "# ",
    "sub_header": "## ",
    "sub_sub_header": "### ",
    "bulleted_list": "- ",
    "numbered_list": "1. ",
    "toggle": "- ",
    "quote": "> ",
    "callout": "> ",
}


def render(blocks, block_id, depth=0, seen=None):
    seen = seen if seen is not None else set()
    if block_id in seen or depth > 6:
        return []
    seen.add(block_id)
    block = blocks.get(block_id)
    if not block:
        return []
    btype = block.get("type")
    text = title_of(block) if block.get("properties") else ""
    pad = "  " * max(0, depth - 1)
    lines = []
    if btype == "divider":
        lines.append(pad + "---")
    elif btype == "to_do":
        checked = (block.get("properties") or {}).get("checked", [["No"]])[0][0] == "Yes"
        lines.append(f"{pad}- [{'x' if checked else ' '}] {text}")
    elif btype == "code":
        lang = rich_text((block.get("properties") or {}).get("language")) or ""
        lines.append(f"{pad}```{lang}\n{text}\n{pad}```")
    elif btype in ("collection_view", "collection_view_page"):
        lines.append(f"{pad}[database {dashed(block_id)}]")
    elif btype == "page":
        lines.append(f"{pad}- [page] {text} ({dashed(block_id)})")
        return lines  # don't recurse into subpages; fetch them separately
    elif text:
        lines.append(pad + PREFIX.get(btype, "") + text)
    for child in block.get("content") or []:
        lines.extend(render(blocks, child, depth + 1, seen))
    return lines


def get_page(page_id, user_id=None):
    pid = dashed(page_id)
    # ponytail: one chunk (~100 blocks). Long pages truncate; add cursor paging if that bites.
    payload = {"pageId": pid, "limit": 100, "cursor": {"stack": []}, "chunkNumber": 0, "verticalColumns": False}
    for uid in [user_id] if user_id else users():
        blocks = {
            k: unwrap(v)
            for k, v in api("loadPageChunk", payload, uid).get("recordMap", {}).get("block", {}).items()
        }
        if pid in blocks:
            break
    else:
        return f"not found or no access: {pid}"
    head = f"# {title_of(blocks[pid])}\nhttps://www.notion.so/{pid.replace('-', '')}\n"
    body = []
    for child in blocks[pid].get("content") or []:
        body.extend(render(blocks, child, 1))
    return head + "\n" + "\n".join(body)


def search(query, space_id=None, limit=10):
    targets = spaces()
    if space_id:
        targets = [t for t in targets if t[0] == space_id] or [(space_id, space_id, None)]
    hits = []
    for sid, name, user_id in targets:
        data = api(
            "search",
            {
                "type": "BlocksInSpace",
                "query": query,
                "spaceId": sid,
                "limit": limit,
                "filters": {
                    "isDeletedOnly": False,
                    "excludeTemplates": False,
                    "navigableBlockContentOnly": True,
                    "requireEditPermissions": False,
                    "includePublicPagesWithoutExplicitAccess": False,
                    "ancestors": [],
                    "createdBy": [],
                    "editedBy": [],
                    "lastEditedTime": {},
                    "createdTime": {},
                },
                "sort": {"field": "relevance"},
                "source": "quick_find_input_change",
            },
            user_id,
        )
        blocks = {k: unwrap(v) for k, v in data.get("recordMap", {}).get("block", {}).items()}
        for r in data.get("results", []):
            bid = r["id"]
            hits.append(
                {
                    "id": dashed(bid),
                    "title": title_of(blocks.get(bid, {})),
                    "workspace": name,
                    "url": f"https://www.notion.so/{bid.replace('-', '')}",
                    "score": r.get("score"),
                }
            )
    hits.sort(key=lambda h: h.get("score") or 0, reverse=True)
    return hits[:limit]


def block_record(block_id):
    """(record, user_id) — which logged-in account can actually see this block."""
    payload = {"requests": [{"pointer": {"table": "block", "id": dashed(block_id)}, "version": -1}]}
    for uid in users():
        rec = api("syncRecordValues", payload, uid).get("recordMap", {}).get("block", {}).get(dashed(block_id))
        if rec and unwrap(rec).get("space_id"):
            return unwrap(rec), uid
    raise ValueError(f"no access to block {block_id}")


def parse_markdown(text):
    """Flat markdown -> Notion block dicts. No nesting; indentation is ignored."""
    blocks = []
    fence, code, lang = False, [], ""
    for line in text.split("\n"):
        if line.startswith("```"):
            if fence:
                blocks.append({"type": "code", "text": "\n".join(code), "language": lang or "Plain Text"})
                fence, code, lang = False, [], ""
            else:
                fence, lang = True, line[3:].strip()
            continue
        if fence:
            code.append(line)
            continue
        s = line.strip()
        if not s:
            blocks.append({"type": "text", "text": ""})
        elif s.startswith("### "):
            blocks.append({"type": "sub_sub_header", "text": s[4:]})
        elif s.startswith("## "):
            blocks.append({"type": "sub_header", "text": s[3:]})
        elif s.startswith("# "):
            blocks.append({"type": "header", "text": s[2:]})
        elif s.startswith("- [ ] ") or s.startswith("- [x] "):
            blocks.append({"type": "to_do", "text": s[6:], "checked": s[3] == "x"})
        elif s.startswith("- ") or s.startswith("* "):
            blocks.append({"type": "bulleted_list", "text": s[2:]})
        elif s.startswith("> "):
            blocks.append({"type": "quote", "text": s[2:]})
        elif s == "---":
            blocks.append({"type": "divider", "text": ""})
        else:
            blocks.append({"type": "text", "text": s})
    if fence:
        blocks.append({"type": "code", "text": "\n".join(code), "language": lang or "Plain Text"})
    return blocks


def block_args(bid, spec, parent_id, parent_table, space_id):
    now = int(time.time() * 1000)
    props = {}
    if spec["text"]:
        props["title"] = [[spec["text"]]]
    if spec["type"] == "to_do":
        props["checked"] = [["Yes" if spec.get("checked") else "No"]]
    if spec.get("language"):
        props["language"] = [[spec["language"]]]
    return {
        "id": bid,
        "version": 1,
        "type": spec["type"],
        "properties": props,
        "created_time": now,
        "last_edited_time": now,
        "created_by_id": USER_ID,
        "created_by_table": "notion_user",
        "last_edited_by_id": USER_ID,
        "last_edited_by_table": "notion_user",
        "parent_id": parent_id,
        "parent_table": parent_table,
        "alive": True,
        "space_id": space_id,
    }


def save(space_id, operations, user_id=None):
    api(
        "saveTransactionsFanout",
        {
            "requestId": str(uuid.uuid4()),
            "transactions": [
                {
                    "id": str(uuid.uuid4()),
                    "spaceId": space_id,
                    "debug": {"userAction": "notion-private-mcp"},
                    "operations": operations,
                }
            ],
        },
        user_id,
    )


def append_blocks(page_id, markdown, parent=None, user_id=None):
    pid = dashed(page_id)
    if parent is None:
        parent, user_id = block_record(pid)
    space_id = parent["space_id"]
    ops = []
    ids = []
    for spec in parse_markdown(markdown):
        bid = str(uuid.uuid4())
        ids.append(bid)
        ops.append(
            {
                "pointer": {"table": "block", "id": bid, "spaceId": space_id},
                "path": [],
                "command": "update",
                "args": block_args(bid, spec, pid, "block", space_id),
            }
        )
        ops.append(
            {
                "pointer": {"table": "block", "id": pid, "spaceId": space_id},
                "path": ["content"],
                "command": "listAfter",
                "args": {"id": bid},
            }
        )
    save(space_id, ops, user_id)
    return len(ids)


def create_page(parent_page_id, title, markdown=""):
    parent_id = dashed(parent_page_id)
    parent, user_id = block_record(parent_id)
    space_id = parent["space_id"]
    pid = str(uuid.uuid4())
    ops = [
        {
            "pointer": {"table": "block", "id": pid, "spaceId": space_id},
            "path": [],
            "command": "update",
            "args": block_args(pid, {"type": "page", "text": title}, parent_id, "block", space_id),
        },
        {
            "pointer": {"table": "block", "id": parent_id, "spaceId": space_id},
            "path": ["content"],
            "command": "listAfter",
            "args": {"id": pid},
        },
    ]
    save(space_id, ops, user_id)
    if markdown.strip():
        append_blocks(pid, markdown, parent={"space_id": space_id}, user_id=user_id)
    return pid


def delete_page(page_id):
    pid = dashed(page_id)
    block, user_id = block_record(pid)
    space_id = block["space_id"]
    save(
        space_id,
        [
            {
                "pointer": {"table": "block", "id": pid, "spaceId": space_id},
                "path": [],
                "command": "update",
                "args": {"alive": False, "last_edited_time": int(time.time() * 1000)},
            },
            {
                "pointer": {"table": "block", "id": block["parent_id"], "spaceId": space_id},
                "path": ["content"],
                "command": "listRemove",
                "args": {"id": pid},
            },
        ],
        user_id,
    )


TOOLS = [
    {
        "name": "notion_list_spaces",
        "description": "List every Notion workspace this account can reach, including ones where it is only a guest.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "notion_search",
        "description": "Full-text search across Notion workspaces (guest workspaces included). Returns page ids to pass to notion_get_page.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "space_id": {"type": "string", "description": "Restrict to one workspace id; omit to search all."},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
    {
        "name": "notion_get_page",
        "description": "Read a Notion page as markdown-ish text. Accepts a page id or the 32-char id from a Notion URL.",
        "inputSchema": {
            "type": "object",
            "properties": {"page_id": {"type": "string"}},
            "required": ["page_id"],
        },
    },
    {
        "name": "notion_append",
        "description": "Append markdown to the end of a Notion page. Supports headings, bullets, to-dos, quotes, code fences and dividers; no nesting.",
        "inputSchema": {
            "type": "object",
            "properties": {"page_id": {"type": "string"}, "markdown": {"type": "string"}},
            "required": ["page_id", "markdown"],
        },
    },
    {
        "name": "notion_create_page",
        "description": "Create a subpage under an existing page, optionally with markdown body. Returns the new page id.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "parent_page_id": {"type": "string"},
                "title": {"type": "string"},
                "markdown": {"type": "string"},
            },
            "required": ["parent_page_id", "title"],
        },
    },
    {
        "name": "notion_delete_page",
        "description": "Move a page to trash (sets it not-alive and unlinks it from its parent).",
        "inputSchema": {
            "type": "object",
            "properties": {"page_id": {"type": "string"}},
            "required": ["page_id"],
        },
    },
]


def call_tool(name, args):
    if name == "notion_list_spaces":
        return "\n".join(f"{sid}  {n}  (account {uid[:8]})" for sid, n, uid in spaces())
    if name == "notion_search":
        return json.dumps(
            search(args["query"], args.get("space_id"), args.get("limit", 10)),
            ensure_ascii=False,
            indent=2,
        )
    if name == "notion_get_page":
        return get_page(args["page_id"])
    if name == "notion_append":
        return f"appended {append_blocks(args['page_id'], args['markdown'])} blocks"
    if name == "notion_create_page":
        pid = create_page(args["parent_page_id"], args["title"], args.get("markdown", ""))
        return f"created {pid}\nhttps://www.notion.so/{pid.replace('-', '')}"
    if name == "notion_delete_page":
        delete_page(args["page_id"])
        return "moved to trash"
    raise ValueError(f"unknown tool: {name}")


def serve():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method, mid = msg.get("method"), msg.get("id")
        if method == "initialize":
            result = {
                "protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "notion-private", "version": "0.1.0"},
            }
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            params = msg.get("params", {})
            try:
                text = call_tool(params["name"], params.get("arguments") or {})
                result = {"content": [{"type": "text", "text": text}]}
            except (urllib.error.HTTPError, urllib.error.URLError, KeyError, ValueError) as e:
                result = {"content": [{"type": "text", "text": f"error: {e}"}], "isError": True}
        elif mid is None:
            continue  # notification, nothing to answer
        else:
            print(
                json.dumps({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found"}}),
                flush=True,
            )
            continue
        if mid is not None:
            print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}), flush=True)


def selftest():
    found = spaces()
    assert found, "getSpaces returned nothing — token probably expired"
    assert any(n != s for s, n, _ in found), "no workspace names resolved"
    print(f"accounts: {len(users())}, spaces: {len(found)}")
    for sid, name, uid in found:
        print(f"  {sid}  {name}  (account {uid[:8]})")
    hits = search("a", limit=3)
    print(f"search hits: {len(hits)}")
    if hits:
        page = get_page(hits[0]["id"])
        assert page.startswith("# "), page[:100]
        print(f"read page {hits[0]['title']!r}: {len(page)} chars")

    if "--write" in sys.argv:
        # own space only — never scribble in a workspace we're a guest of
        own = [(sid, n, u) for sid, n, u in found if not n.startswith("guest:") and not n.startswith(sid[:8])]
        # prefer the personal space so the test never litters a shared workspace
        own.sort(key=lambda t: 0 if "s Space" in t[1] else 1)
        rm = api("loadUserContent", {}, own[0][2]).get("recordMap", {})
        parent = [
            (unwrap(r)["id"], unwrap(r)["space_id"])
            for r in rm.get("block", {}).values()
            if unwrap(r).get("type") == "page" and unwrap(r).get("space_id") == own[0][0]
        ]
        assert parent, "no page to write under"
        pid = create_page(parent[0][0], "selftest (delete me)", "- [ ] hello\n\n## body\ntext line")
        body = get_page(pid)
        assert "hello" in body and "## body" in body, body
        append_blocks(pid, "appended line")
        assert "appended line" in get_page(pid)
        delete_page(pid)
        assert block_record(pid).get("alive") is False, "page still alive after delete"
        print(f"write cycle ok in {own[0][1]!r} ({pid})")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else serve()
