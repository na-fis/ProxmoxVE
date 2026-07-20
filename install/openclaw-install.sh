#!/usr/bin/env bash

# Copyright (c) 2021-2026 ProxmoxVE Community Scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.ai

if [[ -z "${FUNCTIONS_FILE_PATH:-}" ]]; then
  source <(curl -fsSL https://raw.githubusercontent.com/na-fis/ProxmoxVE/main/misc/install.func)
else
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
fi
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  ca-certificates \
  build-essential \
  python3 \
  python3-pip \
  git \
  curl \
  jq \
  tar
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing OpenClaw Framework"
$STD npm install --global openclaw@latest
msg_ok "Installed OpenClaw"

msg_info "Installing gog (Google Workspace CLI & MCP)"
GOG_URL=$(curl -s https://api.github.com/repos/openclaw/gogcli/releases/latest | jq -r '.assets[]? | select(.name | contains("linux_amd64")) | .browser_download_url' 2>/dev/null | head -n 1)
if [[ -n "$GOG_URL" && "$GOG_URL" != "null" ]]; then
  mkdir -p /tmp/gog_install
  $STD curl -fsSL "$GOG_URL" -o /tmp/gog_install/gog.tar.gz
  tar -xzf /tmp/gog_install/gog.tar.gz -C /tmp/gog_install 2>/dev/null || true
  find /tmp/gog_install -type f \( -name "gog" -o -name "gogcli*" \) -exec mv {} /usr/local/bin/gog \; 2>/dev/null || true
  chmod +x /usr/local/bin/gog 2>/dev/null || true
  rm -rf /tmp/gog_install
  msg_ok "Installed gog"
else
  msg_warn "Could not fetch gog binary - skipping"
fi

msg_info "Creating OpenClaw Workspace & Service"
mkdir -p /opt/openclaw

cat <<EOF >/etc/systemd/system/openclaw.service
[Unit]
Description=OpenClaw AI Gateway Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/openclaw
ExecStart=/usr/local/bin/openclaw start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
