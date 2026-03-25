#!/usr/bin/env bash
# vm-bootstrap.sh — Runs once inside the VM to set up the Claude Code sandbox
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}==> ${NC}$1"; }
success() { echo -e "${GREEN} ✓ ${NC}$1"; }

log "Waiting for apt lock (Ubuntu auto-updater runs on first boot)..."
sudo systemctl disable --now unattended-upgrades 2>/dev/null || true
sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
while sudo fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
      >/dev/null 2>&1; do
  echo "  ... waiting for apt lock"
  sleep 3
done
success "apt lock free"

log "Updating system..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq \
  curl git tmux build-essential wget unzip ufw jq ca-certificates gnupg lsb-release

# ── Docker ────────────────────────────────────────────────────────────────────
log "Installing Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker
success "Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── Node.js via nvm ───────────────────────────────────────────────────────────
log "Installing Node.js (LTS)..."
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts && nvm alias default node
grep -q 'NVM_DIR' ~/.bashrc || cat >> ~/.bashrc << 'BASHRC'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
BASHRC
success "Node $(node --version)"

# ── Python ────────────────────────────────────────────────────────────────────
log "Installing Python..."
sudo apt-get install -y -qq python3 python3-pip python3-venv
success "$(python3 --version)"

# ── Claude Code ───────────────────────────────────────────────────────────────
log "Installing Claude Code..."
npm install -g @anthropic/claude-code
success "Claude Code → $(which claude)"

# ── ttyd ──────────────────────────────────────────────────────────────────────
log "Installing ttyd..."
ARCH=$(uname -m)
[ "$ARCH" = "aarch64" ] && TTYD_BIN="ttyd.aarch64" || TTYD_BIN="ttyd.x86_64"
TTYD_VER=$(curl -fsSL https://api.github.com/repos/tsl0922/ttyd/releases/latest | jq -r .tag_name)
wget -q "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VER}/${TTYD_BIN}" -O /tmp/ttyd
sudo mv /tmp/ttyd /usr/local/bin/ttyd && sudo chmod +x /usr/local/bin/ttyd
success "ttyd ${TTYD_VER}"

# ── Tailscale ─────────────────────────────────────────────────────────────────
log "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
success "Tailscale installed"

# ── Firewall ──────────────────────────────────────────────────────────────────
log "Configuring UFW..."
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 7681/tcp
success "Firewall active"

# ── host.docker.internal resolution ──────────────────────────────────────────
log "Setting up host.docker.internal resolution..."
sudo tee /usr/local/bin/update-host-docker-internal.sh > /dev/null << 'HOSTSCRIPT'
#!/usr/bin/env bash
HOST_IP=$(ip route | grep default | awk '{print $3}')
if [ -n "$HOST_IP" ]; then
  sudo sed -i '/host\.docker\.internal/d' /etc/hosts
  echo "$HOST_IP host.docker.internal" | sudo tee -a /etc/hosts > /dev/null
  echo "host.docker.internal → $HOST_IP"
fi
HOSTSCRIPT
sudo chmod +x /usr/local/bin/update-host-docker-internal.sh

sudo tee /etc/systemd/system/host-docker-internal.service > /dev/null << 'HOSTSVC'
[Unit]
Description=Map host.docker.internal to Mac host IP
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-host-docker-internal.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
HOSTSVC
sudo systemctl daemon-reload
sudo systemctl enable host-docker-internal
sudo systemctl start host-docker-internal
success "host.docker.internal → $(ip route | grep default | awk '{print $3}')"

# ── ttyd systemd service ──────────────────────────────────────────────────────
sudo tee /etc/systemd/system/ttyd.service > /dev/null << 'TTYDEOF'
[Unit]
Description=ttyd Web Terminal
After=network.target

[Service]
Type=simple
User=ubuntu
Environment=HOME=/home/ubuntu
ExecStart=/usr/local/bin/ttyd \
  --port 7681 \
  --writable \
  bash -c "export NVM_DIR=$HOME/.nvm; [ -s $NVM_DIR/nvm.sh ] && . $NVM_DIR/nvm.sh; tmux new-session -A -s monitor"
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
TTYDEOF
sudo systemctl daemon-reload
sudo systemctl enable ttyd
sudo systemctl start ttyd
success "ttyd service enabled"

touch /home/ubuntu/.claude-vm-ready
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅  Bootstrap complete!"
echo " Next: sudo tailscale up  (inside this VM)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
