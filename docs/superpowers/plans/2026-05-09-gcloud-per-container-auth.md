# Per-Container gcloud Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shared host gcloud mount with an opt-in, per-container gcloud auth volume so each project can authenticate to a different Google account.

**Architecture:** Single file change (`claude-docker`). Rename `GCLOUD_LOGIN` → `USE_GCLOUD`, add `GCLOUD_VOL_NAME` variable, swap the host dir mount for a named Docker volume mount (auto-detected on restart), add gcloud volume cleanup to `cmd_clean`.

**Tech Stack:** Bash, Docker named volumes, gcloud CLI (already installed in image)

**Spec:** `docs/superpowers/specs/2026-05-09-gcloud-per-container-auth-design.md`

---

## File Map

| File | Change |
|------|--------|
| `claude-docker` | Only file modified — variables, mount logic, startup cmd, clean cmd, flag parse, usage |

---

### Task 1: Rename variable, add GCLOUD_VOL_NAME, update flag parse and usage

**Files:**
- Modify: `claude-docker:38-41` (variables block)
- Modify: `claude-docker:264` (usage text)
- Modify: `claude-docker:272` (flag parse)

- [ ] **Step 1: Replace GCLOUD_LOGIN variable with USE_GCLOUD and add GCLOUD_VOL_NAME**

Find this block (lines 38–41):
```bash
VOLUME_NAME="claude-docker-nm-${PROJECT_NAME}"

USE_TMUX=false
GCLOUD_LOGIN=false
```

Replace with:
```bash
VOLUME_NAME="claude-docker-nm-${PROJECT_NAME}"
GCLOUD_VOL_NAME="claude-docker-gcloud-${PROJECT_NAME}"

USE_TMUX=false
USE_GCLOUD=false
```

- [ ] **Step 2: Update flag parse**

Find (line ~272):
```bash
    --gcloud-login) GCLOUD_LOGIN=true; shift ;;
```

Replace with:
```bash
    --gcloud) USE_GCLOUD=true; shift ;;
```

- [ ] **Step 3: Update usage text**

Find (line ~264):
```bash
  echo "    --gcloud-login          Run gcloud auth login before starting Claude"
```

Replace with:
```bash
  echo "    --gcloud            Mount per-project gcloud auth (login on first run, persists until clean)"
```

- [ ] **Step 4: Check syntax**

```bash
bash -n claude-docker
```

Expected: no output (clean parse)

- [ ] **Step 5: Commit**

```bash
git add claude-docker
git commit -m "refactor: rename GCLOUD_LOGIN to USE_GCLOUD, add GCLOUD_VOL_NAME"
```

---

### Task 2: Update cmd_run — remove host mount, add per-container volume logic

**Files:**
- Modify: `claude-docker:124` (remove host mount)
- Modify: `claude-docker:124` (add volume mount logic)
- Modify: `claude-docker:152-153` (update startup_cmd login block)

- [ ] **Step 1: Remove host gcloud mount, add per-container volume mount**

Find (line ~124):
```bash
  [ -d "$HOME/.config/gcloud" ] && vol_flags+=(-v "$HOME/.config/gcloud:/home/claude/.config/gcloud")
```

Replace with:
```bash
  if [ "$USE_GCLOUD" = true ] || docker volume inspect "$GCLOUD_VOL_NAME" &>/dev/null 2>&1; then
    vol_flags+=(-v "${GCLOUD_VOL_NAME}:/home/claude/.config/gcloud")
  fi
```

- [ ] **Step 2: Update startup_cmd login block to use USE_GCLOUD**

Find (lines ~152–153):
```bash
  if [ "$GCLOUD_LOGIN" = true ]; then
    startup_cmd="${startup_cmd}echo '==> Running gcloud auth login...' && gcloud auth login --no-launch-browser && gcloud auth application-default login --no-launch-browser; "
  fi
```

Replace with:
```bash
  if [ "$USE_GCLOUD" = true ]; then
    startup_cmd="${startup_cmd}echo '==> Running gcloud auth login...' && gcloud auth login --no-launch-browser && gcloud auth application-default login --no-launch-browser; "
  fi
```

- [ ] **Step 3: Check syntax**

```bash
bash -n claude-docker
```

Expected: no output

- [ ] **Step 4: Verify no remaining GCLOUD_LOGIN references**

```bash
grep -n "GCLOUD_LOGIN" claude-docker
```

Expected: no output

- [ ] **Step 5: Commit**

```bash
git add claude-docker
git commit -m "feat: per-container gcloud auth via named Docker volume"
```

---

### Task 3: Update cmd_clean to remove gcloud volume

**Files:**
- Modify: `claude-docker:226-232` (cmd_clean body)

- [ ] **Step 1: Add gcloud volume removal to cmd_clean**

Find:
```bash
cmd_clean() {
  check_prereqs
  log "Removing container '$CONTAINER_NAME'..."
  docker rm -f "$CONTAINER_NAME" 2>/dev/null && success "Container removed" || warn "Container not found"
  log "Removing volume '$VOLUME_NAME'..."
  docker volume rm "$VOLUME_NAME" 2>/dev/null && success "Volume removed" || warn "Volume not found"
}
```

Replace with:
```bash
cmd_clean() {
  check_prereqs
  log "Removing container '$CONTAINER_NAME'..."
  docker rm -f "$CONTAINER_NAME" 2>/dev/null && success "Container removed" || warn "Container not found"
  log "Removing volume '$VOLUME_NAME'..."
  docker volume rm "$VOLUME_NAME" 2>/dev/null && success "Volume removed" || warn "Volume not found"
  log "Removing gcloud volume '$GCLOUD_VOL_NAME'..."
  docker volume rm "$GCLOUD_VOL_NAME" 2>/dev/null && success "gcloud volume removed" || warn "gcloud volume not found"
}
```

- [ ] **Step 2: Check syntax**

```bash
bash -n claude-docker
```

Expected: no output

- [ ] **Step 3: Commit**

```bash
git add claude-docker
git commit -m "feat: remove gcloud volume on claude-docker clean"
```

---

### Task 4: Manual end-to-end verification

- [ ] **Step 1: Verify no-gcloud default — no volume, no mount**

From any project dir:
```bash
claude-docker --help
```

Expected: `--gcloud` listed (not `--gcloud-login`)

- [ ] **Step 2: Verify no gcloud by default**

```bash
# Start container without --gcloud, then in another terminal:
docker inspect claude-docker-<project-name> --format '{{range .Mounts}}{{.Destination}} {{end}}'
```

Expected: `/home/claude/.config/gcloud` NOT in output

- [ ] **Step 3: Verify --gcloud creates volume and triggers login**

```bash
claude-docker --gcloud
# Complete gcloud auth login interactively
# Then stop the container (Ctrl-C or claude-docker stop)
```

Check volume exists:
```bash
docker volume ls | grep gcloud
```

Expected: `claude-docker-gcloud-<project-name>` listed

- [ ] **Step 4: Verify restart auto-mounts without flag**

```bash
claude-docker   # no --gcloud flag
# In another terminal:
docker inspect claude-docker-<project-name> --format '{{range .Mounts}}{{.Destination}} {{end}}'
```

Expected: `/home/claude/.config/gcloud` IS in output (volume auto-detected)

- [ ] **Step 5: Verify clean removes gcloud volume**

```bash
claude-docker clean
docker volume ls | grep gcloud
```

Expected: `claude-docker-gcloud-<project-name>` NOT listed

- [ ] **Step 6: Verify host gcloud is no longer leaked**

Ensure `~/.config/gcloud` exists on host, start container without `--gcloud`:
```bash
docker inspect claude-docker-<project-name> --format '{{range .Mounts}}{{.Source}} → {{.Destination}}
{{end}}'
```

Expected: no line containing `.config/gcloud` from host path
