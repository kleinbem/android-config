#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Fleet Termux Provisioning Script
# Sets up 1-tap Herdr, fleet SSH config, and smart mesh/LAN auto-fallback.
# Works across any Android device (Tablet, Phone, etc.).
# ==============================================================================
set -euo pipefail

DEVICE_NAME="${1:-$(getprop ro.product.model 2>/dev/null || echo "device")}"
# printf, not echo: a trailing newline would become a trailing "-" in the tag.
DEVICE_TAG="$(printf '%s' "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
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

# 3. Fleet hosts in their own file, included from ~/.ssh/config so the
# user's own entries survive a re-run.
FLEET_SSH_CONF="$HOME/.ssh/kleinbem-fleet.conf"
cat <<'EOF' >"$FLEET_SSH_CONF"
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
chmod 600 "$FLEET_SSH_CONF"
touch ~/.ssh/config
if ! grep -qxF "Include $FLEET_SSH_CONF" ~/.ssh/config; then
  # Include must come before any Host block to apply globally.
  { echo "Include $FLEET_SSH_CONF"; echo; cat ~/.ssh/config; } >~/.ssh/config.new
  mv ~/.ssh/config.new ~/.ssh/config
fi
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

# 5. Shell profile integration: one managed block, replaced on re-run;
# the rest of each rc file stays as the user wrote it.
BEGIN_MARK="# >>> kleinbem fleet >>>"
END_MARK="# <<< kleinbem fleet <<<"
FLEET_BLOCK="$BEGIN_MARK
alias corepi=\"ssh corepi\"
alias hass=\"ssh hass\"
alias nas=\"ssh nas\"
alias orin=\"ssh orin\"
$END_MARK"

# Deletes the lines from $2 to $3 (exact lines) in file $1, but only when
# both are there: a range without its end would take the rest of the file.
remove_block() {
  local f="$1"
  [ -f "$f" ] || return 0
  awk -v b="$2" -v e="$3" '
    !inb && $0 == b { inb = 1; buf = $0 "\n"; next }
    inb { buf = buf $0 "\n"; if ($0 == e) { inb = 0; buf = "" }; next }
    { print }
    END { if (inb) { printf "%s", buf; exit 3 } }
  ' "$f" >"$f.tmp" || { rm -f "$f.tmp"; return 1; }
  mv "$f.tmp" "$f"
}

# Appending to a file without a final newline would join the last line.
append_line() {
  local f="$1"
  touch "$f"
  [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ] && echo >>"$f"
  printf '%s\n' "$2" >>"$f"
}

install_block() {
  # An unclosed block left as is: a new end marker after it would let the
  # next run delete the user's lines in between.
  if ! remove_block "$1" "$BEGIN_MARK" "$END_MARK"; then
    echo "⚠️  $1 has \"$BEGIN_MARK\" without \"$END_MARK\"; fix it by hand, skipped." >&2
    return 0
  fi
  append_line "$1" "$FLEET_BLOCK"
}

install_block ~/.bashrc
[ -f ~/.zshrc ] && install_block ~/.zshrc

touch ~/.bash_profile
grep -qxF '[[ -f ~/.bashrc ]] && source ~/.bashrc' ~/.bash_profile ||
  append_line ~/.bash_profile '[[ -f ~/.bashrc ]] && source ~/.bashrc'

echo "✅ Provisioning complete for $DEVICE_NAME!"
echo "🚀 Type 'herdr' to connect."
