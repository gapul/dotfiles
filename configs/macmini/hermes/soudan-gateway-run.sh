#!/bin/bash
# The third Hermes instance ("soudan"): a Discord bot that anyone in one server may talk to.
# Its own HOME gives it its own config, memory, sessions and api_server port, and keeps it out of
# the other two instances' state. Its tools run in the hsoudan sandbox (terminal.backend: ssh).
export HOME=/Users/hermes/soudan-home
export PATH=/Users/hermes/.local/bin:/opt/homebrew/bin:/usr/bin:/bin
# launchd has no TTY to answer the hook prompt.
export HERMES_ACCEPT_HOOKS=1
# The ACP path flattens images to text, so the vision pre-pass always fails; claude-acp attaches
# the files itself.
export HERMES_DISABLE_IMAGE_PREANALYSIS=1
cd /Users/hermes/soudan-home || exit 1
exec /Users/hermes/.local/bin/hermes gateway
