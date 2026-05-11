# Shared pnpm store for claude-docker containers

**Date:** 2026-05-11
**Status:** Approved

## Problem

`claude-docker` currently mounts the macOS host's pnpm store into each
container at `/home/claude/.pnpm-store`. Inside the container the project's
`node_modules` is provided by a per-project Docker named volume. These two
locations live on different filesystems (macOS bind mount vs Docker ext4/btrfs), so
pnpm cannot hardlink from the store into `node_modules`. When hardlinking
fails, pnpm falls back to creating a project-local `.pnpm-store` directory
inside the project tree and copying files. On large workspaces (e.g.
`mavie-api` with ~1700 packages) this copy can fail with `ERR_PNPM_ENOMEM`
and pollutes the project directory.

The goal: every project's container should reuse a single content-addressed
package store with on-disk dedup between the store and each project's
`node_modules`, so installs are fast, disk usage stays low, and no
`.pnpm-store` directories appear inside project trees.

## Filesystem reality on OrbStack / Docker Desktop

OrbStack stores Docker volumes as **btrfs subvolumes**, one per named volume.
Two key consequences:

1. **Hardlinks across volumes are blocked.** `link()` between two named volumes
   returns `EXDEV` (cross-device) even though they share the same physical
   block device — btrfs subvolume isolation prevents cross-subvolume hard
   links.
2. **Reflinks (CoW copies via `FICLONE`) work across volumes.** A file copied
   with `cp --reflink=always` or with `copyFileSync(..., COPYFILE_FICLONE)`
   ends up sharing physical extents with its source.

pnpm's default `package-import-method=auto` does not reliably pick reflinks
in this environment — it falls back to plain copies, resulting in fully
duplicated bytes in every project's `node_modules`. Forcing
`package-import-method=clone-or-copy` makes pnpm use `FICLONE` first, which
succeeds, and CoW-shares blocks between the store and each `node_modules`.

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

Both volumes live on Docker's underlying filesystem. With
`package-import-method=clone-or-copy` configured (see below), pnpm uses
reflinks (CoW) where the filesystem supports them (btrfs on OrbStack) or
copies where it does not. Either way, pnpm never falls back to a
project-local `.pnpm-store`. On btrfs reflinks deliver near-zero extra
on-disk bytes per project; on plain ext4 each project's `node_modules`
holds an independent copy (still acceptable — the goal of avoiding
re-downloads is met by the shared store, and node_modules per-project
isolation is preserved).

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
volume on first use, then write `~/.npmrc` so any pnpm version (including
corepack-pinned ones via `packageManager` in `package.json`) picks up both
the store location and the import method:

```bash
if [[ "$pkg_cmd" == "pnpm install" ]]; then
  startup_cmd="${startup_cmd}sudo chown claude:claude /home/claude/.pnpm-store; "
  startup_cmd="${startup_cmd}command -v pnpm >/dev/null || sudo npm install -g pnpm; "
  startup_cmd="${startup_cmd}echo 'store-dir=/home/claude/.pnpm-store' > /home/claude/.npmrc; "
  startup_cmd="${startup_cmd}echo 'package-import-method=clone-or-copy' >> /home/claude/.npmrc; "
fi
```

**Why `~/.npmrc` instead of `pnpm config set --global`:** when a project pins
its pnpm version via the `packageManager` field in `package.json`, corepack
runs that specific pnpm version for installs. That corepack-pinned binary
and the globally-installed pnpm can disagree about where the "global" pnpm
config lives, so `pnpm config set --global` written by one is not read by
the other. `~/.npmrc` is read by every pnpm version.

**Why `clone-or-copy`:** pnpm's default `auto` import method does not
reliably pick reflinks on btrfs (OrbStack), falling back to plain copies and
duplicating every byte in `node_modules`. Forcing `clone-or-copy` makes pnpm
attempt `FICLONE` first, which succeeds on btrfs and shares blocks between
the store and `node_modules`. On filesystems that don't support reflinks the
fallback is plain copy — the same as the current behavior, no regression.

**Subset store (expected, small):** When pnpm sees that the configured store
and the project root are on different filesystems (the project tree is a
macOS bind mount; the configured store is on the Docker btrfs volume), it
creates a small "subset store" at `<project>/.pnpm-store/` on the macOS
side. With `clone-or-copy` this subset store stays tiny — empirically
around 40MB even for a 1700-package workspace — because it only holds
metadata, the pnpm binary itself (corepack stages it here), and a small
index. The actual package bytes never get duplicated into the subset
store; they're reflinked from the Docker-volume store directly into
`node_modules`. A pre-fix run that fell back to plain copy mode produced a
much larger subset store (~1.3GB) — those stale directories should be
deleted manually after deploying this change.

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

3. **Block-level dedup verified inside container**

   On btrfs (OrbStack), reflinks share blocks even though each file is a
   distinct inode (link count = 1). Use `filefrag` to detect the `shared`
   extent flag:

   ```bash
   claude-docker shell
   count=0; total=0
   for f in $(find node_modules -type f 2>/dev/null | head -200); do
     total=$((total+1))
     filefrag -v "$f" 2>/dev/null | grep -q "shared" && count=$((count+1))
   done
   echo "$count/$total node_modules files share blocks with store"
   ```

   Expected on btrfs: a high ratio (≥ 95%) of files report `shared`. On
   filesystems that don't support reflinks, expect 0 — that is acceptable
   (the shared store still avoids re-downloads, just no block-level dedup).

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
