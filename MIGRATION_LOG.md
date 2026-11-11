# Migration Log

Dated, running checklist for the ARIA backend migration (Hetzner → new
server). Check items off as they're actually done, not planned. Secret
rotations are logged by **key name only** — never values.

---

## 2026-11-05 — Repo created

- [x] Created `aria-infra-migration` (private) to track this migration
- [x] Added `RUNBOOK.md` (full migration plan, pasted by founder)

---

## 2026-11-10/11 — Plan changed: old server was gone, not migrated

The old Hetzner server was deleted by the host before Phase 0 started
(non-payment, confirmed no Hetzner account access or backup exists). This
invalidated the runbook's "migrate existing code + ChromaDB data" plan —
there was nothing left to migrate. Also discovered the richer backend the
runbook describes (`routes/`, `integrations/`, `<aria_meta>` parsing,
`kb_pending` approval loop, agent dashboard, per-client KB namespacing,
Supabase wiring) was never pushed to git — only a 171-line skeleton
(`itsmundhir/reachbridge-web`'s `aria/main.py`) existed in version control.
Founder confirmed no current client depends on this backend, so there was
no live outage to manage, just a rebuild decision.

Decision: full rebuild of the backend to match the runbook's spec, rather
than a minimal relaunch of the skeleton file, since the richer feature set
was lost either way and is worth having. Separately, Supabase itself is
now fully paused (unrelated billing issue) and was replaced earlier this
week by a self-hosted Postgres + PostgREST + Express API on the same
OVHcloud server already running the main dashboard — so ARIA's backend
was built against *that* Postgres instance from the start, not Supabase.

- [x] Confirmed old server unreachable (SSH host key changed, HTTPS down) — deleted, not just suspended
- [x] Confirmed no Hetzner account access, no backup of ChromaDB or server-only code
- [x] Confirmed no current client depends on this backend (no live outage)
- [x] Rebuilt backend from scratch in `itsmundhir/reachbridge-web`'s `aria/` directory: Postgres persistence (`conversations`/`messages`/`escalations`/`kb_pending`/`client_ai_config`/`knowledge_base` — all survived the earlier pg_dumpall restore intact), per-client ChromaDB namespacing (`client_{client_id}`, fixing the old cross-client KB isolation gap), `<aria_meta>` confidence/escalation parsing, Slack+HubSpot escalation integrations, `kb_pending` approval loop, agent dashboard (`agent_dashboard.html`)
- [x] Deployed to the existing OVHcloud box (`vps-cf180e77`) rather than a new dedicated server — founder's call given recent payment issues; can move to dedicated hardware later if resource contention becomes real
- [x] Tested end-to-end: chat response + KB retrieval + confidence scoring + escalation (keyword-triggered) + agent queue listing, all against real Postgres data
- [x] Caddy route added, HTTPS working (`aria-test.supanta.com` test subdomain, then `api.supanta.com` itself)
- [x] **DNS cutover done** — `api.supanta.com` now points to the OVHcloud server (`158.69.233.123`), old Hetzner IP (`167.233.85.235`) fully retired
- [ ] Fresh Slack bot token + HubSpot token (old ones compromised per runbook, never rotated — still outstanding, escalation code no-ops gracefully without them)
- [ ] Embeddable chat widget JS (`widget/aria-widget.js`) — also lost with the old server, not yet rebuilt
- [ ] Anthropic API key reused from the main dashboard's `.env` (generated fresh this week, not the Hetzner-exposed one — compliant with "rotate, don't reuse compromised secrets," just noting it's shared across both services)

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
