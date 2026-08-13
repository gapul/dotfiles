#!/bin/bash
export HOME=/Users/hermes
export PATH=/Users/hermes/.local/bin:/opt/homebrew/bin:/usr/bin:/bin
cd /Users/hermes || exit 1
exec /Users/hermes/.local/bin/hermes gateway
