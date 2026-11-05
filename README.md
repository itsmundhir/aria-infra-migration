# aria-infra-migration

Tracks the migration of the **ARIA backend** (FastAPI + ChromaDB + Claude API,
currently on a Hetzner Cloud VPS) to a new cloud server.

This is **not** the app code repo — that's `itsmundhir/aria` (or wherever
`aria/main.py` actually lives; confirm at Phase 0). This repo holds:

- `RUNBOOK.md` — the full migration plan and product/architecture context.
  **This is the source of truth for this project. Read it before doing
  anything else.** It covers what's moving, what must not be touched
  (Supabase, Netlify, Anthropic-side config), the exact phase-by-phase
  runbook, every integration that needs re-pointing, and the standing
  product rules (naming, content compliance, escalation flow) that this
  migration must not silently break.
- `MIGRATION_LOG.md` — the dated, running checklist. Update this as each
  phase/step completes. Secret rotations are logged by **key name only,
  never by value**.
- `infra/` — Caddyfile, systemd unit, and `.env.example` (keys only).
  Placeholders until Phase 0 captures the real ones off the old server.
- `scripts/` — deployment scripts for the new server.

## Why this is a separate repo

This migration is unrelated to any Supabase/Postgres data-layer work on
`supanta-web`. ARIA talks to Supabase as a record store only, and this
migration explicitly does not touch Supabase, Netlify, or Anthropic-side
config beyond re-pointing URLs that reference the old server's IP/domain.

## Status

Not started. See `MIGRATION_LOG.md`.
