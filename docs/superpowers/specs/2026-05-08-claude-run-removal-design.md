# Design: Remove claude-run (Multipass VM Backend)

**Date:** 2026-05-08  
**Status:** Approved

## Summary

Remove all Multipass VM backend code and documentation. The project is Docker-only going forward.

## Files to Delete

- `claude-run` — Multipass VM launch script
- `vm-bootstrap.sh` — VM provisioning script (runs once inside the VM)

## Makefile Changes

- `install`: remove `claude-run` copy step, remove `vm-bootstrap.sh` copy step, update success message to mention only `claude-docker`
- `uninstall`: remove `claude-run` removal line, drop the multipass hint in the output
- `update`: remove claude-run mention from success message
- Delete `bootstrap-local` target (copies vm-bootstrap.sh — VM-only, no longer relevant)
- Delete `status` target (shells out to `claude-run status`)

## README Changes

- **Requirements**: remove Multipass + Tailscale line
- **Quick start**: remove "Option B: Multipass VM" section; rename "Option A: Docker" to plain Docker section (drop the A/B framing)
- **Usage**: remove entire "Usage — claude-run" section
- **Isolation**: remove `claude-run` isolation table, keep only `claude-docker` table
- **Node.js / native binaries**: remove claude-run paragraph, keep Docker paragraph
- **Repo structure**: remove `claude-run` and `vm-bootstrap.sh` entries
- **Cleanup**: remove Multipass block, keep Docker block only

## Out of Scope

- No changes to `Dockerfile.claude`, `claude-docker`, or `settings.claude.example.json`
- No new features
