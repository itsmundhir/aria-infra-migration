# Migration Log

Dated, running checklist for the ARIA backend migration (Hetzner → new
server). Check items off as they're actually done, not planned. Secret
rotations are logged by **key name only** — never values.

---

## 2026-11-05 — Repo created

- [x] Created `aria-infra-migration` (private) to track this migration
- [x] Added `RUNBOOK.md` (full migration plan, pasted by founder)
- [ ] New server provisioned and reachable
- [ ] Phase 0 (prep / capture current state) started

---

## Phase 0 — Prep (no production risk)

- [ ] Captured actual `.env` key list from old server (confirm against RUNBOOK's expected list)
- [ ] Confirmed live model string in `main.py` / `core/llm.py`
- [ ] Confirmed live confidence/escalation threshold (expect `0.45`)
- [ ] Captured `chromadb/` directory size (`du -sh`)
- [ ] Captured real `aria.service` unit file
- [ ] Captured real Caddy config
- [ ] Pushed captured (non-secret) config into this repo as documentation

## Phase 1 — Provision new server

- [ ] New server provisioned (≥ 4 vCPU / 8GB RAM, Ubuntu LTS)
- [ ] `deploy` user created, sudo enabled, SSH key copied
- [ ] Root login disabled, password auth disabled (check `sshd_config.d/*.conf` too)
- [ ] UFW: OpenSSH, 80, 443 only
- [ ] Caddy, Python 3.11+, git installed (confirm if ffmpeg actually needed)
- [ ] Caddyfile restored/adapted for new box

## Phase 2 — Rotate secrets (log key NAMES only below once rotated)

- [ ] Anthropic API key
- [ ] HubSpot token
- [ ] Slack bot token
- [ ] Postmark server token
- [ ] GitHub personal access token (old deploy pipeline)
- [ ] Supabase service key + hook secret (rotate in Supabase dashboard AND update both consumers — new server `.env` and Supabase Edge Function secrets)
- [ ] New `.env` written directly on new server (never via chat/screenshot)

## Phase 3 — Move code and data

- [ ] App repo cloned, venv set up, dependencies installed
- [ ] `chromadb/` directory copied from old → new server
- [ ] File count/size verified to match before proceeding
- [ ] Supabase Auth Hook signature bug fixed (Standard Webhooks verification, not Bearer)
- [ ] systemd unit set up on new server

## Phase 4 — Verify before cutover

- [ ] `/health` responds on new server's own IP
- [ ] `/chat` (or equivalent) retrieves correctly from migrated ChromaDB (tested against a known KB answer)
- [ ] Low-confidence query still triggers Slack + HubSpot escalation
- [ ] Test invite confirms Auth Hook fix works end-to-end

## Phase 5 — Cutover

- [ ] DNS TTL lowered in advance
- [ ] `api` A record (Squarespace DNS) repointed to new IP — root domain MX/SPF untouched
- [ ] Twilio voice webhook updated in console (only if voice is live and domain changes)
- [ ] Logs watched on both servers during propagation
- [ ] Old server kept running untouched for 24–48h rollback window

## Phase 6 — Decommission

- [ ] Stability confirmed for the agreed period (no errors, escalations firing, KB retrieval correct)
- [ ] Old Hetzner server decommissioned
- [ ] Final log entry: what moved, what was rotated (names only), what's still outstanding

---

## Outstanding issues (pre-existing, not introduced by this migration)

- [ ] KB/client isolation gap — ChromaDB not namespaced by `client_id`; one KB for one client. Flag to founder if multiple clients now exist. Do not silently add namespacing without sign-off.
- [ ] Google Workspace billing risk — repeated payment-decline notices on `supanta.com`'s Workspace subscription. Not this migration's job to fix, just flag.
