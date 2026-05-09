# gh Per-Container Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--gh` flag to `claude-docker` that sets up per-container GitHub CLI auth via a fine-grained PAT, scoped to repos the user selects, persisted in a named Docker volume.

**Architecture:** Mirrors the existing `--gcloud` pattern exactly — named Docker volume per project holds `~/.config/gh`, created on first `--gh` run after interactive PAT entry, mounted silently on subsequent restarts if the volume exists.

**Tech Stack:** Bash, Docker named volumes, `gh` CLI (GitHub official apt package), `shellcheck` for linting.

---

## File Map

| File | Change |
|---|---|
| `Dockerfile.claude` | Add `gh` installation via GitHub's official apt repo |
| `claude-docker` | Add `USE_GH` var, `GH_VOL_NAME` var, `--gh` flag, mount logic, auth startup cmd, clean cmd, usage text |

---

### Task 1: Add `gh` to the Docker image

**Files:**
- Modify: `Dockerfile.claude`

- [ ] **Step 1: Add gh installation block**

Open `Dockerfile.claude`. After the gcloud block (the `RUN curl -fsSL https://packages.cloud.google.com/apt...` block ending with `rm -rf /var/lib/apt/lists/*`), insert this new `RUN` layer **before** the `ARG HOST_UID` line:

```dockerfile
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Build the image and verify `gh` is available**

```bash
docker build -t claude-code-sandbox --build-arg HOST_UID=$(id -u) -f Dockerfile.claude .
docker run --rm claude-code-sandbox -c "gh --version"
```

Expected output: `gh version 2.x.x (...)` — any version line means success.

- [ ] **Step 3: Commit**

```bash
git add Dockerfile.claude
git commit -m "feat: install gh CLI in Docker image"
```

---

### Task 2: Add variables and flag parsing to `claude-docker`

**Files:**
- Modify: `claude-docker`

- [ ] **Step 1: Add `GH_VOL_NAME` next to `GCLOUD_VOL_NAME`**

Find this block (around line 22):
```bash
CONTAINER_NAME="claude-docker-${PROJECT_NAME}"
VOLUME_NAME="claude-docker-nm-${PROJECT_NAME}"
GCLOUD_VOL_NAME="claude-docker-gcloud-${PROJECT_NAME}"
```

Add one line after `GCLOUD_VOL_NAME`:
```bash
GH_VOL_NAME="claude-docker-gh-${PROJECT_NAME}"
```

- [ ] **Step 2: Add `USE_GH=false` next to `USE_GCLOUD=false`**

Find:
```bash
USE_TMUX=false
USE_GCLOUD=false
```

Add one line after `USE_GCLOUD=false`:
```bash
USE_GH=false
```

- [ ] **Step 3: Add `--gh` to the flag parse loop**

Find:
```bash
    --gcloud) USE_GCLOUD=true; shift ;;
```

Add one line after it:
```bash
    --gh) USE_GH=true; shift ;;
```

- [ ] **Step 4: Lint**

```bash
shellcheck claude-docker
```

Expected: no errors or warnings.

- [ ] **Step 5: Smoke test — help still works**

```bash
./claude-docker help
```

Expected: usage text prints without error.

- [ ] **Step 6: Commit**

```bash
git add claude-docker
git commit -m "feat: add USE_GH var and --gh flag parsing"
```

---

### Task 3: Add gh volume mount logic to `cmd_run`

**Files:**
- Modify: `claude-docker`

- [ ] **Step 1: Add mount block after the gcloud mount block**

Find this block inside `cmd_run`:
```bash
  if [ "$USE_GCLOUD" = true ] || docker volume inspect "$GCLOUD_VOL_NAME" &>/dev/null; then
    vol_flags+=(-v "${GCLOUD_VOL_NAME}:/home/claude/.config/gcloud")
  fi
```

Add immediately after it:
```bash
  if [ "$USE_GH" = true ] || docker volume inspect "$GH_VOL_NAME" &>/dev/null; then
    vol_flags+=(-v "${GH_VOL_NAME}:/home/claude/.config/gh")
  fi
```

- [ ] **Step 2: Lint**

```bash
shellcheck claude-docker
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add claude-docker
git commit -m "feat: mount per-project gh volume in cmd_run"
```

---

### Task 4: Add gh auth startup command

**Files:**
- Modify: `claude-docker`

- [ ] **Step 1: Add auth block after the gcloud auth block**

Find this block inside `cmd_run`:
```bash
  if [ "$USE_GCLOUD" = true ]; then
    startup_cmd="${startup_cmd}sudo chown -R claude:claude /home/claude/.config/gcloud; echo '==> Running gcloud auth login...' && gcloud auth login --no-launch-browser && gcloud auth application-default login --no-launch-browser; "
  fi
```

Add immediately after it:
```bash
  if [ "$USE_GH" = true ]; then
    startup_cmd="${startup_cmd}sudo chown -R claude:claude /home/claude/.config/gh; "
    startup_cmd="${startup_cmd}echo '' && echo '==> GitHub auth — create a fine-grained PAT:' && echo '    https://github.com/settings/personal-access-tokens/new?description=claude-docker-${PROJECT_NAME}' && echo '    Select repos to allow, set permissions, then paste the token:' && printf 'Token: ' && read -r _GH_TOKEN && echo \"\$_GH_TOKEN\" | gh auth login --with-token; "
  fi
```

Note: `_GH_TOKEN` uses an underscore prefix to avoid colliding with the `GH_TOKEN` env var that `gh` itself reads. `sudo chown` is required because Docker creates named volumes owned by root.

- [ ] **Step 2: Lint**

```bash
shellcheck claude-docker
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add claude-docker
git commit -m "feat: add gh auth flow to startup command"
```

---

### Task 5: Add gh volume cleanup and update usage text

**Files:**
- Modify: `claude-docker`

- [ ] **Step 1: Add gh volume removal to `cmd_clean`**

Find this block inside `cmd_clean`:
```bash
  log "Removing gcloud volume '$GCLOUD_VOL_NAME'..."
  docker volume rm "$GCLOUD_VOL_NAME" 2>/dev/null && success "gcloud volume removed" || warn "gcloud volume not found"
```

Add immediately after it:
```bash
  log "Removing gh volume '$GH_VOL_NAME'..."
  docker volume rm "$GH_VOL_NAME" 2>/dev/null && success "gh volume removed" || warn "gh volume not found"
```

- [ ] **Step 2: Add `--gh` to the usage text**

Find the Flags section inside `usage()`:
```bash
  echo "    --gcloud            Mount per-project gcloud auth (login on first run, persists until clean)"
```

Add one line after it:
```bash
  echo "    --gh                Fine-grained GitHub PAT auth (scoped to selected repos, persists until clean)"
```

- [ ] **Step 3: Verify usage output**

```bash
./claude-docker help
```

Expected: `--gh` line appears under Flags.

- [ ] **Step 4: Lint**

```bash
shellcheck claude-docker
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add claude-docker
git commit -m "feat: add gh volume cleanup and --gh usage text"
```

---

### Task 6: Integration test

No automated test harness exists for this script. Verify manually:

- [ ] **Step 1: Confirm image has `gh`**

```bash
docker run --rm claude-code-sandbox -c "gh --version"
```

Expected: version line printed.

- [ ] **Step 2: Confirm no gh volume exists for current project**

```bash
docker volume ls | grep gh
```

Expected: no `claude-docker-gh-*` volumes (clean state).

- [ ] **Step 3: Test `--gh` flag is accepted**

```bash
./claude-docker --gh help 2>&1 | head -5
```

Expected: usage text prints (flag parsed, no "unknown flag" error). This does not start a full container — `help` exits immediately after flag parsing.

- [ ] **Step 4: Test `clean` removes gh volume (if one exists from manual testing)**

If you ran a full `claude-docker --gh` and a volume was created:
```bash
docker volume ls | grep "gh"
./claude-docker clean
docker volume ls | grep "gh"
```

Expected: volume absent after `clean`.

- [ ] **Step 5: Run `make install` to update the installed script**

```bash
make install
```

Expected: `claude-docker` copied to `/usr/local/bin/claude-docker` without errors.
