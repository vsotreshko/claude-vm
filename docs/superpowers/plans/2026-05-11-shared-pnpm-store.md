# Shared pnpm Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken host-store bind mount with a single global Docker named volume so every `claude-docker` container shares one pnpm content-addressed store on the same filesystem as the per-project `node_modules` volume, enabling hardlinks and eliminating project-local `.pnpm-store` fallbacks.

**Architecture:** A new global Docker volume `claude-docker-pnpm-store` is mounted at `/home/claude/.pnpm-store` whenever the detected package manager is pnpm. The volume is shared across all projects, so packages are downloaded once and reused via hardlinks into the per-project `node_modules` volume. Per-project `clean` leaves the shared store alone; `purge` removes it via its existing `name=claude-docker-` filter.

**Tech Stack:** Bash, Docker named volumes, pnpm.

**Spec:** [`docs/superpowers/specs/2026-05-11-shared-pnpm-store-design.md`](../specs/2026-05-11-shared-pnpm-store-design.md)

---

## File Structure

Only one file changes:

- Modify: `claude-docker` — bash CLI entry point. Three small edits: add a volume-name constant, replace the host-store detection block with a shared-volume mount, update the pnpm portion of the container startup command to chown the freshly mounted volume and set the pnpm store-dir.

No other files need changes:
- `Dockerfile.claude` — unchanged. pnpm install (when missing) still happens at runtime inside the container as today.
- `Makefile` — unchanged. `make install` copies the edited script as today.
- README / docs — unchanged. Internal behavior change only.

---

## Task 1: Add shared pnpm store volume to `claude-docker`

**Files:**
- Modify: `/Users/vsotreshko/Projects/claude-vm/claude-docker`

This task makes all three coordinated edits in one commit. They are interdependent — applying any one alone leaves the script in a broken or no-op state, so split commits would create unnecessarily broken intermediate states.

- [ ] **Step 1: Add the volume-name constant**

Use the Edit tool with `replace_all: false`:

`old_string`:

```
GH_VOL_NAME="claude-docker-gh-${PROJECT_NAME}"

USE_TMUX=false
```

`new_string`:

```
GH_VOL_NAME="claude-docker-gh-${PROJECT_NAME}"
PNPM_STORE_VOL_NAME="claude-docker-pnpm-store"

USE_TMUX=false
```

The new constant is intentionally **not** suffixed with `${PROJECT_NAME}` — the whole point is that the volume is global, shared by every project.

- [ ] **Step 2: Replace the host-store detection block with a shared-volume mount**

Use the Edit tool with `replace_all: false`:

`old_string`:

```
  # Build startup command
  local pkg_cmd
  pkg_cmd="$(detect_pkg_manager)"

  # Share host pnpm store with container to avoid re-downloading packages
  local pnpm_store=""
  if [[ "$pkg_cmd" == "pnpm install" ]] && command -v pnpm &>/dev/null; then
    pnpm_store="$(pnpm store path 2>/dev/null | sed 's|/v[0-9].*||')"
  fi
  if [ -n "$pnpm_store" ]; then
    vol_flags+=(-v "$pnpm_store:/home/claude/.pnpm-store")
  fi
```

`new_string`:

```
  # Build startup command
  local pkg_cmd
  pkg_cmd="$(detect_pkg_manager)"

  # Share pnpm content-addressed store across all claude-docker containers.
  # Lives on the same Docker filesystem as the per-project node_modules
  # volume, so pnpm can hardlink and avoid project-local .pnpm-store fallback.
  if [[ "$pkg_cmd" == "pnpm install" ]]; then
    vol_flags+=(-v "${PNPM_STORE_VOL_NAME}:/home/claude/.pnpm-store")
  fi
```

This drops the dependency on having pnpm installed on the macOS host (the old code called `pnpm store path` on the host).

- [ ] **Step 3: Update the pnpm portion of the startup command**

Use the Edit tool with `replace_all: false`:

`old_string`:

```
  # Install pnpm if needed
  if [[ "$pkg_cmd" == "pnpm install" ]]; then
    startup_cmd="${startup_cmd}command -v pnpm >/dev/null || sudo npm install -g pnpm; pnpm config set --global store-dir /home/claude/.pnpm-store; "
  fi
```

`new_string`:

```
  # Ensure pnpm is installed, fix ownership on the freshly mounted shared
  # store volume (Docker creates it root-owned), and point pnpm at it.
  if [[ "$pkg_cmd" == "pnpm install" ]]; then
    startup_cmd="${startup_cmd}sudo chown claude:claude /home/claude/.pnpm-store; "
    startup_cmd="${startup_cmd}command -v pnpm >/dev/null || sudo npm install -g pnpm; "
    startup_cmd="${startup_cmd}pnpm config set --global store-dir /home/claude/.pnpm-store; "
  fi
```

Important details:
- `chown` is **not** recursive. The top-level dir is the only thing that needs ownership flipped: Docker creates the empty volume root-owned, but everything pnpm subsequently writes inside it will already be owned by `claude`. A recursive chown over a 5–20 GB store would be slow on every container start.
- The chown must come before `pnpm config set` and any install, so pnpm has write access to the store directory.
- Order of statements inside `startup_cmd` matters: each new line appends to the running command string, so the three new statements must run in the order written above.

- [ ] **Step 4: Syntax-check the script**

Run:

```bash
bash -n /Users/vsotreshko/Projects/claude-vm/claude-docker
```

Expected: no output, exit code 0. Any syntax error must be fixed before continuing.

If `shellcheck` is available, also run:

```bash
shellcheck /Users/vsotreshko/Projects/claude-vm/claude-docker
```

Treat any new warning introduced by this change as a failure (pre-existing warnings can be ignored).

- [ ] **Step 5: Inspect the diff**

Run:

```bash
git -C /Users/vsotreshko/Projects/claude-vm diff -- claude-docker
```

Expected: exactly the three edits above. Confirm:
- One new constant line `PNPM_STORE_VOL_NAME="claude-docker-pnpm-store"`.
- The old `pnpm_store="$(pnpm store path ...)` block is gone.
- The new `vol_flags+=(-v "${PNPM_STORE_VOL_NAME}:...)` mount block is present.
- The startup pnpm block contains three statements in the order: chown, install-pnpm-if-missing, `pnpm config set`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/vsotreshko/Projects/claude-vm add claude-docker
git -C /Users/vsotreshko/Projects/claude-vm commit -m "feat: share pnpm store across containers via global Docker volume"
```

---

## Task 2: Install and verify the change

This is verification, not new code. Each step has an explicit expected outcome.

**Files:** none modified.

- [ ] **Step 1: Install the updated script**

Run:

```bash
cd /Users/vsotreshko/Projects/claude-vm
make install
```

Expected: prints `==> Installing claude-docker to /usr/local/bin...` and a success line. May prompt for sudo password.

Verify the installed copy matches the repo copy:

```bash
diff /usr/local/bin/claude-docker /Users/vsotreshko/Projects/claude-vm/claude-docker
```

Expected: no output (identical).

- [ ] **Step 2: Reset prior state**

Wipe all existing claude-docker containers and per-project node_modules volumes so the next run is a true cold cache for the new store volume:

```bash
claude-docker purge
```

Type `yes` at the confirmation prompt.

Expected output: lists containers and volumes to delete, then "Purge complete." Confirm the shared store volume does not exist yet:

```bash
docker volume ls | grep claude-docker-pnpm-store || echo "not yet — expected"
```

Expected: prints `not yet — expected`.

- [ ] **Step 3: Cold-cache first run**

```bash
cd /Users/vsotreshko/Projects/_youtube/yt-content-planner
claude-docker
```

Expected progression:
1. `==> Starting container 'claude-docker-yt-content-planner'...`
2. `==> Installing dependencies...` followed by pnpm output.
3. **No `ERR_PNPM_ENOMEM`** anywhere in the output.
4. Eventually Claude Code starts.

Once Claude starts, exit it (`/exit` or Ctrl-D) so we can run the verification steps. The container will stop.

Now from the host, verify no project-local `.pnpm-store` was created:

```bash
ls -la /Users/vsotreshko/Projects/_youtube/yt-content-planner/.pnpm-store 2>/dev/null \
  && echo "FAIL: project-local store exists" \
  || echo "OK: no project-local store"
```

Expected: `OK: no project-local store`.

- [ ] **Step 4: Confirm the shared volume exists and has content**

```bash
docker volume inspect claude-docker-pnpm-store
```

Expected: a JSON object with the volume name and mountpoint. (Note: on Docker Desktop / OrbStack the mountpoint path is inside the VM and may not be browsable from macOS; that's fine.)

Confirm it actually has content via a throwaway container:

```bash
docker run --rm -v claude-docker-pnpm-store:/store alpine sh -c 'du -sh /store && ls /store | head'
```

Expected: a non-zero size (typically tens to hundreds of MB after a fresh install) and a `v3` or similar pnpm directory listed.

- [ ] **Step 5: Verify hardlinks from node_modules into the store**

Restart the container in shell mode:

```bash
cd /Users/vsotreshko/Projects/_youtube/yt-content-planner
claude-docker shell
```

Inside the container shell, find any installed package's `package.json` under `node_modules/.pnpm/` and check its link count:

```bash
target=$(find node_modules/.pnpm -mindepth 4 -name package.json -type f 2>/dev/null | head -1)
echo "Inspecting: $target"
stat -c 'links=%h' "$target"
exit
```

Expected: `links=2` (or higher). A value of `1` means the file is **not** hardlinked to the store and the design is failing — investigate before continuing.

- [ ] **Step 6: Warm-cache second project**

Pick any other pnpm-based project on the machine (a different repo than `yt-content-planner`). Example:

```bash
fd -HI -t f pnpm-lock.yaml /Users/vsotreshko/Projects --max-depth 4 | head
```

Pick one (call its directory `OTHER`), then:

```bash
cd "$OTHER"
claude-docker
```

Expected:
- Install runs again (this project's `node_modules` Docker volume is still empty), but pnpm reports most packages as reused / hardlinked rather than downloaded.
- Wall-clock time is markedly shorter than Step 3's cold install.
- No `.pnpm-store` appears inside `$OTHER`.

Exit Claude again so the container stops.

- [ ] **Step 7: `clean` preserves the shared store**

Pick the second project from Step 6 (or `yt-content-planner`) and clean it:

```bash
claude-docker clean
```

Expected: removes the container and the per-project `claude-docker-nm-<project>` volume. Then verify the shared store is still present:

```bash
docker volume ls | grep claude-docker-pnpm-store
```

Expected: one line listing `claude-docker-pnpm-store`. If it is gone, `cmd_clean` is over-eager and the spec is violated — fix before declaring done.

- [ ] **Step 8: Record verification outcome**

No code change. Confirm in writing (chat reply or commit message) that Steps 1–7 all met their expected outcomes. If anything failed, do **not** mark the plan complete — return to Task 1 to fix.

---

## Notes on what is intentionally NOT in this plan

- **No automated test harness.** `claude-docker` is a thin bash wrapper around `docker run`; the meaningful behavior under test (Docker volume mounting, pnpm hardlinking) cannot be unit-tested in isolation without standing up Docker, which is exactly what the manual smoke test in Task 2 does. Adding a test framework here would be more code than the change itself.
- **No host-store seeding.** The brainstorming session explicitly rejected approach B (copying the host pnpm store into the Docker volume on first run). The shared store re-downloads packages the first time per cache miss and then never again.
- **No `.gitignore` updates in user projects.** That is a per-project housekeeping concern outside this repo, and the design already prevents new `.pnpm-store` directories from being created.
