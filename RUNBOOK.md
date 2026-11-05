# ARIA / Supanta Backend Migration — Runbook

> Pasted verbatim from the founder on 2026-11-05. This is the source of
> truth for this migration — read it in full before touching anything.
> `MIGRATION_LOG.md` tracks actual progress against the phases below;
> this file itself should only change if the founder revises the plan.

---

## CONTEXT — READ FIRST, DO NOT SKIP

You are migrating the backend for **ARIA**, the AI support agent that powers **Supanta** (Pty) Ltd, a South African remote-first BPO agency (formerly branded "ReachBridge" — never use that name or `reachbridgeagency.com` in anything you write or commit; current domain is `supanta.com`). The founder is Mundhir Adams.

The task: migrate ARIA's FastAPI backend off its current Hetzner Cloud VPS onto a new cloud server, with zero data loss and minimal downtime, while rotating every exposed secret in the process.

### Current (source) server

- **Host:** Hetzner Cloud, CPX32 (4 vCPU / 8GB RAM / 160GB NVMe), region `nbg1` (Nuremberg)
- **IP:** `167.233.85.235`
- **Domain:** `api.supanta.com` → A record to this IP (DNS managed via Squarespace Domains; root domain MX points to Google Workspace — do NOT touch root MX/SPF when you repoint the subdomain)
- **OS:** Ubuntu
- **Access:** `deploy` user, key-only SSH, sudo enabled. Root SSH login is disabled and password auth is disabled. UFW firewall allows only OpenSSH, 80, 443.
- **Reverse proxy / TLS:** **Caddy** (automatic HTTPS) — not Nginx/Certbot, despite what an earlier planning doc said.
- **Process manager:** systemd unit `aria.service` running `uvicorn main:app` from a Python venv.
- **App path:** `/home/deploy/aria-backend/`
- **Repo:** GitHub `itsmundhir/reachbridge-web`, backend code lives at `aria/main.py` in that repo (repo name is legacy-branded; do not rename mid-migration unless asked — just don't let the old name leak into user-facing content)
- **Vector store:** **ChromaDB** with `sentence-transformers` embeddings (`all-MiniLM-L6-v2`), persisted on disk at `/home/deploy/aria-backend/chromadb/`. **This is stateful data — the actual knowledge base. It must be copied to the new server, not just the code.** An old design doc describes a pure in-memory store with no ChromaDB dependency — that doc is stale; ChromaDB is what's actually deployed.
- **Model:** confirm the live model string on the server before assuming anything (it was corrected once already via `sed` from `claude-sonnet-4-20250514` to `claude-sonnet-4-6` — check `main.py` / `core/llm.py` for whatever string is actually there now and preserve it unless told to change it).
- **Confidence/escalation threshold:** **0.45** is the confirmed, live, production-calibrated value (based on `top1` similarity on retrieved chunks). Earlier values of 0.58 and 0.75 appear in older docs/configs — they are superseded. Carry forward 0.45 unless you find the live `.env` or `client_ai_config` says otherwise, in which case trust what's actually running over any document.
- **Deployment workflow in use:** edit locally → push to GitHub → `curl` (GitHub-token-authenticated) pulls onto the server → `sudo systemctl restart aria`. There's also a paramiko-based local script (`server.py`) for running remote commands without a fresh SSH session each time. You can replace this workflow with something better during migration (e.g. a proper CI/CD or `git pull` + deploy hook) — the founder has no attachment to the old process and explicitly dislikes manual terminal typing.

### Environment variables (`.env` at `/home/deploy/aria-backend/.env`)

Keys present (treat every value as **compromised** — several were exposed via screenshots and must be rotated, not just copied):
```
ANTHROPIC_API_KEY
SLACK_BOT_TOKEN
SLACK_CHANNEL
SLACK_CHANNEL_ID
HUBSPOT_TOKEN
SUPPORT_EMAIL_ADDRESS        # currently info@supanta.com
DEFAULT_CLIENT_ID
SUPABASE_SERVICE_KEY
SUPABASE_HOOK_SECRET
POSTMARK_SERVER_TOKEN
SUPABASE_URL
```
Also present in some builds: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`, `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID` — check what's actually wired up before assuming voice is live.

**Explicitly flagged as compromised and needing rotation:** Anthropic API key, HubSpot token, Slack bot token, GitHub personal access token, Postmark server token (confirmed unrotated as of last check — treat as burned). Rotate ALL of these as part of this migration, writing fresh values only into the new server's `.env`. Never log, print, or commit any of these values in plaintext anywhere — not in commit messages, not in the new GitHub repo, not in chat output.

### Distributed architecture (only ONE of these three nodes is moving)

```
Netlify (static widget, zero credentials)
   → POST to api.supanta.com  [THIS IS THE PIECE THAT MOVES]
        FastAPI + ChromaDB + rate limiting (slowapi) + CORS + Caddy HTTPS
        holds SUPABASE_SERVICE_KEY, never exposed to the browser
   → Anthropic Claude API (reasoning only, nothing stored there — unaffected)
   → Supabase (conversations, messages, escalations, kb_pending, client_ai_config
     — record store only, unaffected by this migration)
```
Do not touch Netlify, Supabase, or Anthropic-side config beyond re-pointing URLs that reference the old server's IP/domain.

### Integrations that must be re-pointed or re-verified after cutover

1. **Postmark** — inbound webhook for stream `aria-inbound` currently points to `https://api.supanta.com/email/inbound`. If the domain stays the same and only the IP changes, this needs no edit in Postmark — just confirm the new server actually answers on that path once DNS cuts over.
2. **Supabase Auth "Send Email" hook** — points to `https://api.supanta.com/auth/send-email`, authenticated via **Standard Webhooks** signing (`webhook-id`/`webhook-timestamp`/`webhook-signature` headers, verified using `SUPABASE_HOOK_SECRET`) — **not** a plain `Authorization: Bearer` header. There is a known, not-yet-fixed bug here: the hook currently 500s with "Hook requires authorization token," which strongly suggests the handler is checking for the wrong header type. **Fix this during the migration** using the `standardwebhooks` Python library to verify signatures correctly, then test with a real invite before declaring migration done.
3. **Twilio voice webhook** (if voice is live) — set in the Twilio console, not in code, to `https://<old-ip-or-domain>/api/v1/voice/inbound`. Must be manually updated in the Twilio console post-cutover if the IP changes.
4. **Netlify chat widget** (`aria-widget.js`) — has `API_BASE` hardcoded to the backend URL. If the domain `api.supanta.com` is preserved and just repointed in DNS, no redeploy needed. If the URL changes at all, redeploy the widget to Netlify with the new `API_BASE`.
5. **Slack app "ARIA Escalations"** (`chat:write` scope, channel `#aria-escalations`, channel ID `C0BCF2WV8GG`) — no change needed, this is Slack-side.
6. **HubSpot** — ticket creation via REST, no change needed unless the token is rotated (it is — update `.env`).

### Known unresolved issues — do not treat these as newly discovered, they're pre-existing

- **KB/client isolation gap:** ChromaDB's knowledge base is NOT currently scoped by `client_id` to match Supabase's per-client config — there's effectively one KB for one client. If multiple clients now exist, flag this to the founder before/during migration rather than silently replicating the gap onto the new server.
- **Invite-flow 500 (see Supabase Auth hook above)** — fix this now, it's a good opportunity since you're touching the email/auth code path anyway.
- **Google Workspace billing risk:** `supanta.com`'s Google Workspace subscription has had repeated payment-decline notices. If it lapses, all `@supanta.com` mail breaks regardless of server migration — mention this to the founder, don't attempt to fix Workspace billing yourself.

### Communication style for this session

Mundhir prefers short, direct, results-first responses. No long explanations unless something is genuinely ambiguous or risky. Don't ask permission for routine steps — flag and stop only for irreversible actions (DNS cutover, deleting the old server, secret rotation that could lock out access) or genuine ambiguity.

---

## FULL ARIA PRODUCT CONTEXT — what you're actually migrating, not just where it runs

This section exists because a migration that only moves bytes but loses the *why* behind them tends to reintroduce bugs that were already fixed, or break rules that were already decided. Read this before touching code, not just the infra section above.

### Product suite naming — CRITICAL, do not leak these publicly

ReachBridge/Supanta's internal product suite has named layers:
- **ARIA** — cyan, robot icon — the AI chat/voice agent (what this migration is about)
- **RELAY** — amber, switch icon — the human handoff layer (not ARIA itself; the escalation/agent-takeover UX)
- **NEXUS** — purple, topology icon — intelligence/data hub (largely conceptual, not fully built)
- **PULSE** — red, activity icon — the analytics dashboard (deflection rate, CSAT, SLA, agent performance) — deprioritized until after first live client generates real data
- **FLOW** — green, branch icon — workflow automation engine (Phase 2, not built)
- **BRIDGE** — blue, bridge icon — the platform layer tying them together (name conflicts with the old "ReachBridge" company name — flagged as potentially confusing, never resolved)

**Hard rule from the content compliance checklist: none of these whitelabel feature names (ARIA, PULSE, FLOW, NEXUS) may appear in public-facing copy.** They're internal/engineering names only. If Claude Code is asked to update anything client-facing (widget copy, landing pages, docs) during this migration, strip these names out — refer to "the AI agent," "the analytics dashboard," etc. instead. This is a standing rule, not new guidance for this task.

### Full content compliance checklist (applies to ANY copy this migration touches, including code comments visible to clients, error messages, email templates)

- No em dashes anywhere
- No fabricated statistics, no client-count claims, no cost-comparison framing
- No "ReachBridge" or "reachbridgeagency.com" — company is Supanta (Pty) Ltd, domain `supanta.com`
- No "AI does the work, humans bring the value" framing
- No "60% cheaper" / "60% less than in-house" claims
- No whitelabel product names (ARIA, PULSE, FLOW, NEXUS) in anything public-facing
- Preferred tone words: innovation, intelligent, seamless, modern. Slogan: **"Smart Support. Real People."**
- Canonical CTA is always "book a call" — pricing is never shown on `supanta.com` and is hard-blocked in ARIA's own responses (if a user asks ARIA about pricing, it must redirect to booking a call, never quote a number)

### ARIA's actual conversational architecture (the `<aria_meta>` pattern)

Every Claude API response ARIA generates returns a hidden JSON block (`<aria_meta>`) carrying confidence (0–1), sentiment, and escalation reason. This is the entire mechanism by which ARIA decides it's out of its depth — there are no hardcoded keyword rules driving the primary decision (the `ESCALATION_TRIGGERS` keyword list seen in `crm_router.py` is a secondary/backup check, not the main signal). **When migrating or touching this code, preserve the `<aria_meta>` parsing — don't let a refactor accidentally start relying on keyword matching alone.**

### Full escalation flow (KB miss → human → KB improvement loop)

This is the complete loop, not just "Slack fires":
1. User asks something ARIA can't answer confidently (confidence < 0.45)
2. ARIA tells the user it's looping in a specialist
3. A HubSpot ticket is created, tagged `[KB Miss]`
4. An agent is pinged via Slack webhook with the question and a dashboard deep link
5. ARIA stays in the conversation (doesn't drop the user)
6. Agent submits an answer via `POST /agent/answer`
7. ARIA reformats and relays the agent's answer back to the user
8. Claude auto-generates a KB article title from the Q&A
9. The Q&A is inserted into `kb_pending` for human approval
10. Once approved, it becomes part of the live KB — this is how the KB actually grows over time, not just manual uploads

There's a full **agent dashboard** (`agent_dashboard.html`, single-file HTML) supporting this: a KB-miss queue with 30-second polling, an answer panel showing the conversation thread, a KB-pending approval section, and a settings panel persisting to `localStorage`. Design system: Sora + DM Sans fonts, `#00c2ff` cyan accent, dark theme (`#070c14` base). If this dashboard exists on the old server as a static file, it needs to move too — check for it, it's easy to miss since it's not part of the FastAPI app itself.

### Data isolation guarantee (verify this survives migration intact)

- Every Supabase table has `client_id NOT NULL` — no row exists without a client owner
- RLS policies enforce client-scoped reads at the database level (already audited/fixed — 19 recursive policies corrected to use the `is_admin()` SECURITY DEFINER helper)
- FastAPI filters by `client_id` in every query as defense-in-depth
- **ChromaDB collections are supposed to be namespaced as `client_{client_id}`** for zero cross-client vector bleed — but this was flagged elsewhere as NOT actually implemented yet (one KB, one client, no real isolation tested). **Verify which state is true on the current server before migrating** — if collections aren't namespaced, don't invent namespacing during migration without the founder's sign-off, since it could silently change retrieval behavior; just carry over whatever currently exists and flag the gap in `MIGRATION_LOG.md`.
- A person confirmed this requirement explicitly: ARIA must never use information across client companies.

### Business rules that constrain what this migration should and shouldn't do

- **Service lines (current, as of Nov 2026):** consolidated down to two — **Tech Support** and **Data & CRM Operations** (renamed from "Customer Support" and "Back-Office Operations" respectively). Sales/SDR was dropped as a service line entirely. `supanta.com/services` is the live reference.
- **Voice is deferred** — Twilio/VoIP is not to be built or prioritized until chat is proven. Gates: 100% of escalations must reach a human with full context, AND a paying client must explicitly request phone support. Don't "helpfully" wire up voice during this migration unless those gates are already met — check with the founder if voice code is found live.
- **Never build write-action capabilities speculatively** — ARIA and its integrations should stay read-mostly unless a real client need justifies a write action, prototyped against one real prospect first. The MSA liability cap was drafted for a support-chatbot risk profile and would need revisiting before any write-action feature ships — don't add new write capabilities as a side effect of migration work.
- **Threading rule:** a support ticket is one issue, not one customer — the same issue across channels (matched by `thread_ref`) is one ticket; different issues from the same customer are separate tickets even if concurrently open. This matters if you touch `thread_inbound_message()` or any ticket-creation logic during migration.
- **KB discipline:** nothing enters the KB unless explicitly confirmed in prior conversations with the founder — no padding with plausible-sounding copy, inferred details, or aspirational descriptions. This applies to you too, Claude Code: don't backfill or "improve" KB content while migrating it, just move it faithfully.
- **Infrastructure-over-sales is a known founder trap** — Mundhir has a documented pattern of delaying outreach in favor of build work. If this migration starts growing scope (e.g. "let's also add multi-tenant KB namespacing properly," "let's also build FLOW"), that's scope creep against a known pattern — flag it rather than just doing it, even if it seems like obviously good engineering.

### HubSpot integration flow (for context when touching `hubspot_client.py` / `crm_router.py`)

```
User message → ARIA → escalation triggered
→ HubSpot contact created/matched by email
→ HubSpot ticket created with conversation context
→ Ticket associated with contact
→ conversation.hubspot_ticket_id updated in Supabase
```

### Full 17-file build-guide structure (cross-reference against what's ACTUALLY on the server — several of these diverged in production, as noted in the infra section above: ChromaDB vs in-memory, Caddy vs Nginx)

```
aria/
├── main.py                       # FastAPI entrypoint, CORS, router registration
├── config.py / config/settings.py  # Pydantic settings, env var loading
├── requirements.txt
├── .env                          # never commit
├── core/
│   ├── rag.py                    # KnowledgeBase class: ingest, chunk, embed, retrieve
│   ├── llm.py                    # Claude API wrapper, system prompt template
│   ├── embeddings.py             # SentenceTransformer singleton
│   └── conversation.py           # session store (in-memory Phase 1; TODO Phase 2 → Postgres)
├── routes/
│   ├── chat.py                   # POST /chat
│   ├── voice.py                  # Twilio TwiML handlers (if voice is live)
│   ├── escalation.py             # manual escalation trigger
│   └── analytics.py              # session counts, deflection rate, CSAT stub
├── integrations/
│   ├── slack_client.py           # send_escalation_alert() — Block Kit formatting
│   ├── hubspot_client.py         # create_ticket() via REST
│   └── crm_router.py             # should_escalate() keyword backup logic, trigger_escalation()
├── widget/aria-widget.js         # chat widget — deployed separately to Netlify
├── agent_dashboard.html          # agent-facing KB-miss/approval UI (verify it exists on old server)
└── tests/test_rag.py
```

### Known architectural decisions worth knowing even though they don't change code

- KB quality determines ARIA's deflection rate, not code quality — thin/disorganized KBs cause hallucinations. Supanta builds and maintains client KBs during onboarding, not the client. This is why protecting the ChromaDB data during migration (flagged in the infra section) matters so much — it's the actual product value, not an implementation detail.
- The confidence threshold has moved over time: `0.75` (original design default) → `0.65` (interim) → `0.58` (calibrated against real logged data) → **`0.45` (final, confirmed live)**. Don't "fix" it back to an earlier value if you find an old doc suggesting otherwise — 0.45 is correct unless the founder says differently.

---

## TASK 1 — Create a private GitHub repo for this migration

Before touching any server, create a **new private GitHub repository** on Mundhir's account (`itsmundhir`) to track the migration itself — infra-as-code, runbook notes, deployment scripts, and a record of what changed. Suggested name: `aria-infra-migration` (confirm with the founder if a different name is preferred). This repo is separate from `itsmundhir/reachbridge-web` (the app code) — it's specifically for the migration's scripts, systemd units, Caddyfile, nginx/caddy config, and a `MIGRATION_LOG.md` tracking what's been done, what's pending, and which secrets were rotated (names only, never values).

> **Status: done.** This repo is that repo. (Created 2026-11-05.)

Initialize it with:
```
README.md          # what this repo is for
MIGRATION_LOG.md    # dated checklist, updated as you go
infra/
  Caddyfile
  aria.service       # systemd unit
  .env.example        # keys only, no values
scripts/
  deploy.sh           # whatever replaces the old curl-pull-restart flow
```

---

## TASK 2 — Migration runbook (execute in this order)

### Phase 0 — Prep (no production risk)
1. On the **old** server, confirm the live state of truth before copying anything:
   - `cat /home/deploy/aria-backend/.env` → note which keys are actually set (don't just trust the list above)
   - Check `main.py` / `core/llm.py` for the actual model string in use
   - Check the actual confidence threshold value in code/config (expect `0.45`, verify)
   - `du -sh /home/deploy/aria-backend/chromadb/` → confirm it exists and note its size
   - `systemctl status aria` and `cat /etc/systemd/system/aria.service` → capture the real unit file
   - Caddy config (`/etc/caddy/Caddyfile` or wherever it lives) → capture it
2. Push all of the above (minus secret *values*) into the new `aria-infra-migration` repo as the starting documentation.

### Phase 1 — Provision new server
3. Provision the new box. Match or exceed CPX32 spec: **4 vCPU / 8GB RAM minimum** — this is a hard floor because sentence-transformers + concurrent Claude API calls created real memory pressure on smaller tiers previously. Ubuntu LTS.
4. Harden it the same way as the old server:
   - Create `deploy` user, add to sudo, copy SSH key via `rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy`
   - `PermitRootLogin no`, `PasswordAuthentication no` in `/etc/ssh/sshd_config` (check `/etc/ssh/sshd_config.d/*.conf` too — some distros override the main file there)
   - UFW: allow OpenSSH, 80, 443 only
   - Install Caddy, Python 3.11+, git, ffmpeg (ffmpeg was in the original build guide's dependency list — confirm if actually used)
5. Install Caddy and restore the captured Caddyfile, updated for the new box.

### Phase 2 — Rotate secrets (do this before moving data, not after)
6. Rotate, in this order, generating fresh values and recording only key *names* (never values) in `MIGRATION_LOG.md`:
   - Anthropic API key
   - HubSpot token
   - Slack bot token
   - Postmark server token
   - GitHub personal access token (used by the old deploy pipeline)
   - Supabase service key and hook secret — rotate via the Supabase dashboard; this requires re-saving the new value into whatever consumes it (both the new server's `.env` AND Supabase Edge Function secrets, since some keys like `ANTHROPIC_API_KEY` exist in both places independently)
7. Write the new `.env` directly on the new server — never through a file that transits an insecure channel (no screenshots, no pasting into chat logs).

### Phase 3 — Move code and data
8. Clone the app repo onto the new server, set up the venv, `pip install -r requirements.txt`.
9. **Copy the `chromadb/` directory from the old server to the new one** (e.g. `rsync -avz deploy@<old-ip>:/home/deploy/aria-backend/chromadb/ /home/deploy/aria-backend/chromadb/`). Verify file count/size matches before proceeding — this is the actual knowledge base and losing it silently degrades ARIA without an obvious error.
10. Fix the Supabase Auth Hook signature verification bug now (Standard Webhooks, not Bearer token) while you're in this code path.
11. Set up the systemd unit on the new server matching the captured one, adjusted for any path changes.

### Phase 4 — Verify before cutover
12. With the new server live on its own IP (not yet pointed at `api.supanta.com`), smoke test directly against the IP:
    - `/health` endpoint
    - `/chat` or `/api/v1/chat` with a real query, confirm it retrieves from the migrated ChromaDB correctly (test a question you know the answer should be in the KB)
    - Trigger a low-confidence query and confirm Slack + HubSpot escalation still fires
    - Send a test invite and confirm the Auth Hook fix actually resolves the "Hook requires authorization token" error end-to-end
13. Only once all of the above pass, proceed to cutover.

### Phase 5 — Cutover
14. Lower DNS TTL in advance if not already low.
15. Repoint the `api` A record (Squarespace DNS) from the old IP to the new IP. Do **not** touch the root domain's MX/SPF records.
16. If Twilio voice is live, update the voice webhook URL in the Twilio console to match (same domain, so only needed if the domain itself changes — otherwise skip).
17. Watch both old and new server logs during propagation. Keep the old server running and untouched for at least 24–48 hours as a rollback path.

### Phase 6 — Decommission
18. After confirming stability (no errors, escalations firing, KB retrieval correct) for an agreed period, decommission the old Hetzner server.
19. Final `MIGRATION_LOG.md` entry: what moved, what was rotated, what's still outstanding (e.g. KB/client isolation gap, Workspace billing risk) — these are pre-existing issues, not introduced by this migration, and should be logged as still-open rather than silently dropped.

---

## Deliverable at end of session

A working ARIA backend on the new server, serving `api.supanta.com`, with:
- All secrets rotated
- ChromaDB KB intact and verified
- Auth Hook signature bug fixed
- A private GitHub repo (`aria-infra-migration`) documenting the whole thing
- A clear, short list (in `MIGRATION_LOG.md`) of anything still outstanding that needs a human decision (e.g. multi-client KB isolation, Workspace billing)

Report progress concisely. Stop and ask before: DNS cutover, decommissioning the old server, or any step that would revoke access to something still in use.
