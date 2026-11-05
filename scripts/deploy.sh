#!/usr/bin/env bash
# PLACEHOLDER — first draft, meant to be refined during Phase 3.
#
# RUNBOOK.md notes the old workflow (push to GitHub -> curl pulls on the
# server -> systemctl restart) can be replaced with something better; the
# founder has no attachment to it and dislikes manual terminal typing.
# This script is a simple starting point: run it ON the new server itself.
# A real CI/CD trigger (e.g. a GitHub webhook calling this script) would
# remove the need to SSH in by hand at all — worth doing once the basic
# migration is stable, not before.

set -euo pipefail

APP_DIR="/home/deploy/aria-backend"
SERVICE="aria"

cd "$APP_DIR"
git pull --ff-only
source venv/bin/activate
pip install -r requirements.txt
deactivate
sudo systemctl restart "$SERVICE"
sudo systemctl status "$SERVICE" --no-pager
