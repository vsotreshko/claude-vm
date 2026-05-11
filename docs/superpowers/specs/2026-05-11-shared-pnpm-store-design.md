# Shared pnpm store for claude-docker containers

**Date:** 2026-05-11
**Status:** Approved

## Problem

`claude-docker` currently mounts the macOS host's pnpm store into each
container at `/home/claude/.pnpm-store`. Inside the container the project's
`node_modules` is provided by a per-project Docker named volume. These two
locations live on different filesystems (macOS bind mount vs Docker ext4), so
pnpm cannot hardlink from the store into `node_modules`. When hardlinking
fails, pnpm falls back to creating a project-local `.pnpm-store` directory
inside the project tree and copying files. On large workspaces (e.g.
`mavie-api` with ~1700 packages) this copy can fail with `ERR_PNPM_ENOMEM`
and pollutes the project directory.

The goal: every project's container should reuse a single content-addressed
package store with working hardlinks, so installs are fast, disk usage stays
low, and no `.pnpm-store` directories appear inside project trees.

## Goals

- Avoid re-downloading packages when starting containers for different
  projects.
- Avoid duplicating package bytes across projects (single shared store).
- Eliminate fallback project-local `.pnpm-store` directories.
- Keep per-project isolation for `node_modules`.

## Non-goals

- Sharing the store with the host's pnpm. The host store is a separate copy.
- Seeding the Docker store from the host store on first run.

## Architecture

### Volume layout

| Name                         | Scope                        | Mount                         | Purpose                                     |
| ---------------------------- | ---------------------------- | ----------------------------- | ------------------------------------------- |
| `claude-docker-pnpm-store`   | global (all containers)      | `/home/claude/.pnpm-store`    | Shared pnpm content-addressed store         |
| `claude-docker-nm-<project>` | per-project (already exists) | `${PROJECT_DIR}/node_modules` | Project dependencies, hardlinked from store |

Both volumes live on Docker's ext4 filesystem. Hardlinks across them succeed,
so pnpm performs no copy and never falls back to a project-local store.

## Implementation

All changes are in `claude-docker`.

### 1. Constant

Add near the other volume name constants (around line 40):

```bash
PNPM_STORE_VOL_NAME="claude-docker-pnpm-store"
```

### 2. Remove host-store mount block

Delete lines 145-152:

```bash
local pnpm_store=""
if [[ "$pkg_cmd" == "pnpm install" ]] && command -v pnpm &>/dev/null; then
  pnpm_store="$(pnpm store path 2>/dev/null | sed 's|/v[0-9].*||')"
fi
if [ -n "$pnpm_store" ]; then
  vol_flags+=(-v "$pnpm_store:/home/claude/.pnpm-store")
fi
```

### 3. Mount shared Docker volume instead

In `cmd_run`, alongside the other `vol_flags` entries, add (only when pnpm is
the package manager):

```bash
if [[ "$pkg_cmd" == "pnpm install" ]]; then
  vol_flags+=(-v "${PNPM_STORE_VOL_NAME}:/home/claude/.pnpm-store")
fi
```

### 4. Startup command

Update the pnpm block (currently lines 164-166) to chown the freshly mounted
volume on first use, then configure store-dir:

```bash
if [[ "$pkg_cmd" == "pnpm install" ]]; then
  startup_cmd="${startup_cmd}sudo chown claude:claude /home/claude/.pnpm-store; "
  startup_cmd="${startup_cmd}command -v pnpm >/dev/null || sudo npm install -g pnpm; "
  startup_cmd="${startup_cmd}pnpm config set --global store-dir /home/claude/.pnpm-store; "
fi
```

### 5. Lifecycle

- `cmd_clean` (per-project): no change. Must NOT remove the shared store
  volume, since other projects still use it.
- `cmd_purge` (global): no change. Existing `name=claude-docker-` filter
  already matches the new volume.
- `cmd_status`: no change.

## Migration

After deploying the new script:

```bash
claude-docker purge
```

That removes all existing claude-docker containers and per-project node_modules
volumes. On next run for any project the shared store volume is auto-created
by Docker.

Host-disk `.pnpm-store` directories created by past fallback runs are NOT
touched by `purge`. Remove them manually:

```bash
fd -HI --prune -t d '^\.pnpm-store$' /Users/vsotreshko/Projects -x rm -rf
```

(`du -sh` first to preview sizes.)

## Testing

1. **Cold cache first run**

   ```bash
   cd /Users/vsotreshko/Projects/_youtube/yt-content-planner
   claude-docker
   ```

   Expected: install runs, downloads packages into the shared store, no
   `.pnpm-store` appears in the project directory, no `ERR_PNPM_ENOMEM`.

2. **Shared store volume exists**

   ```bash
   docker volume inspect claude-docker-pnpm-store
   ```

3. **Hardlinks verified inside container**

   ```bash
   claude-docker shell
   stat -c '%h' node_modules/.pnpm/twilio@*/node_modules/twilio/package.json
   ```

   Expected: link count ≥ 2.

4. **Warm cache on a second project**

   ```bash
   cd <other-pnpm-project>
   claude-docker
   ```

   Expected: install completes quickly, only new (uncached) packages
   download, the rest hardlink from the shared store.

5. **`clean` preserves the shared store**

   ```bash
   claude-docker clean
   docker volume ls | grep claude-docker-pnpm-store
   ```

   Expected: shared store volume still listed.
