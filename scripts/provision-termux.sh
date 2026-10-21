#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Fleet Termux Provisioning Script
# Sets up 1-tap Herdr, fleet SSH config, and smart mesh/LAN auto-fallback.
# Works across any Android device (Tablet, Phone, etc.).
# ==============================================================================
set -euo pipefail

DEVICE_NAME="${1:-$(getprop ro.product.model 2>/dev/null || echo "device")}"
DEVICE_TAG="$(echo "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
PREFIX="/data/data/com.termux/files/usr"

echo "📱 Setting up Termux for device: $DEVICE_NAME ($DEVICE_TAG)..."

# 1. Install prerequisites
echo "📦 Installing openssh and core tools..."
pkg update -y >/dev/null 2>&1 || true
pkg install -y openssh curl jq >/dev/null

# 2. SSH Directory & Keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "🔑 Generating dedicated device SSH key..."
  ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -C "martin-${DEVICE_TAG}-termux"
fi

PUB_KEY="$(cat ~/.ssh/id_ed25519.pub)"
echo "📋 Public key:"
echo "   $PUB_KEY"

# Export key for host retrieval via ADB or file transfer
mkdir -p /sdcard/Download 2>/dev/null || true
echo "$PUB_KEY" >"/sdcard/Download/${DEVICE_TAG}_termux.pub" 2>/dev/null || true

# 3. Fleet ~/.ssh/config
cat <<'EOF' >~/.ssh/config
# ─── Workstation Herdr (Live Agent Session) ───
Host herdr
    HostName 100.117.212.232
    User martin
    IdentityFile ~/.ssh/id_ed25519
    RemoteCommand herdr
    RequestTTY yes
    StrictHostKeyChecking accept-new

Host herdr-lan
    HostName 10.0.0.5
    User martin
    IdentityFile ~/.ssh/id_ed25519
    RemoteCommand herdr
    RequestTTY yes
    StrictHostKeyChecking accept-new

# ─── Workstation Standard Shell ───
Host nvme
    HostName 100.117.212.232
    User martin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nvme-lan
    HostName 10.0.0.5
    User martin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

# ─── Fleet Infrastructure Nodes (NetBird Mesh) ───
Host corepi
    HostName 100.117.146.201
    User martin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host hass
    HostName 100.117.163.227
    User martin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nas
    HostName 100.117.39.136
    User martin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host orin
    HostName 100.117.37.104
    User martin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config

# 4. Smart CLI Launchers in $PREFIX/bin
mkdir -p "$PREFIX/bin"

cat <<'EOF' >"$PREFIX/bin/herdr"
#!/data/data/com.termux/files/usr/bin/bash
if (echo > /dev/tcp/100.117.212.232/22) >/dev/null 2>&1; then
    exec ssh herdr "$@"
elif (echo > /dev/tcp/10.0.0.5/22) >/dev/null 2>&1; then
    exec ssh herdr-lan "$@"
else
    exec ssh herdr "$@"
fi
EOF
chmod +x "$PREFIX/bin/herdr"

cat <<'EOF' >"$PREFIX/bin/herdr-lan"
#!/data/data/com.termux/files/usr/bin/bash
exec ssh herdr-lan "$@"
EOF
chmod +x "$PREFIX/bin/herdr-lan"

cat <<'EOF' >"$PREFIX/bin/herdr-mesh"
#!/data/data/com.termux/files/usr/bin/bash
exec ssh herdr "$@"
EOF
chmod +x "$PREFIX/bin/herdr-mesh"

cat <<'EOF' >"$PREFIX/bin/nvme"
#!/data/data/com.termux/files/usr/bin/bash
if (echo > /dev/tcp/100.117.212.232/22) >/dev/null 2>&1; then
    exec ssh nvme "$@"
elif (echo > /dev/tcp/10.0.0.5/22) >/dev/null 2>&1; then
    exec ssh nvme-lan "$@"
else
    exec ssh nvme "$@"
fi
EOF
chmod +x "$PREFIX/bin/nvme"

cat <<'EOF' >"$PREFIX/bin/nvme-lan"
#!/data/data/com.termux/files/usr/bin/bash
exec ssh nvme-lan "$@"
EOF
chmod +x "$PREFIX/bin/nvme-lan"

cat <<'EOF' >"$PREFIX/bin/agents"
#!/data/data/com.termux/files/usr/bin/bash
exec "$PREFIX/bin/herdr" "$@"
EOF
chmod +x "$PREFIX/bin/agents"

# 5. Shell profile integration
cat <<'EOF' >~/.bashrc
# Kleinbem Fleet shortcuts
alias herdr="herdr"
alias herdr-lan="herdr-lan"
alias nvme="nvme"
alias nvme-lan="nvme-lan"
alias agents="agents"
alias corepi="ssh corepi"
alias hass="ssh hass"
alias nas="ssh nas"
alias orin="ssh orin"
EOF

echo '[[ -f ~/.bashrc ]] && source ~/.bashrc' >~/.bash_profile

if [ -f ~/.zshrc ]; then
  cat ~/.bashrc >~/.zshrc
fi

echo "✅ Provisioning complete for $DEVICE_NAME!"
echo "🚀 Type 'herdr' to connect."
