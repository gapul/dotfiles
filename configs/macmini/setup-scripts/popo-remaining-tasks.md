# Handover: popo-agent chat providers, 2026-07-13

What is left from work done on other machines, the gapul Mac and the ispc Windows machine. Pick
up whatever is workable. The repository is github.com/post-urban/popo-agent, which uses GitHub
Flow with main as the only default and integration branch.

## Already done and on origin

Five feature branches are rebased onto origin/main at #401. Each pull request spells out its
provider-specific limitations and migration caveats.

- Chatwork, PR #403, open: markdown conversion, file transfer both ways, five migrations.
- Telegram, PR #404, open: the full Bot API, five migrations.
- Windows runtime, PR #364, open: native Windows compatibility, an fcntl fix, and a Windows CI
  matrix.
- LINE, PR #405, closed and on hold. The branch feat/chat-line is rebased, at 5e883bed; reopen
  with `gh pr reopen 405`.
- Teams, feat/chat-teams, five commits, neither rebased nor opened as a PR.

## What is left

1. **The teams branch.** Rebase onto origin/main, verify with typecheck and vitest, and open a
   PR. Like the other providers, expect additive conflicts in the shared files —
   chat-egress.ts, inbound.ts, identity.ts, route.ts — and expect
   `buildChatLinkReassignedEmail` and `resolveSeatForSlackSender` to need extending for the new
   provider.
2. **Conflicts between merges.** chatwork, telegram, line and teams all touch the same shared
   files, so after the first one merges the rest need rebasing onto main, with minor conflicts
   to resolve.
3. **Deduplicating token resolution**, optional. Every provider's egress repeats the same
   sequence: resolve apiToken, call resolveRuntimeSecret, and on http_401 refresh and retry
   once. It could collapse into a `resolveXxxToken`.
4. **A deeper audit of the provider diffs**, optional, looking for over-implementation and dead
   code. Chatwork's unwired interactivity-handler has already been deleted. line and teams have
   not been audited.

## Blocked on the ispc Windows machine, reachable as `ssh ispc`

**Chatwork file transfer** needs the existing install re-authorised for the OAuth scopes
`rooms.files:read/write`. Until it is, the API returns 400, and the end-to-end test on real
hardware has not been done. The scopes are already in scopes.ts.

**LINE has not been tested end to end.** Its database is empty. It needs a LINE Messaging API
channel created, a channel token and secret, a webhook at line-test.mugen404.com, a tenant,
install and link, and a message sent from the LINE app. The line worktree on ispc is out of
date, at commit 39d1893a, and its `.env` has `ENTITLEMENT_ISSUER` wrongly set to
host.docker.internal:3000.

**Keeping Windows working** will need attention whenever new fcntl or OS-specific code lands on
main, since the Windows guards have to follow. The Windows CI matrix that was added should catch
it.

## Ground rules

Do not `git add` `data/` or `.env`. Do not delete vault notes directly. Do not write into
`.claude/plans/`.

ispc is a Windows machine, and entering credentials or creating accounts is a human's job.
