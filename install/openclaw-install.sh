#!/usr/bin/env bash

# Copyright (c) 2021-2026 ProxmoxVE Community Scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
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
  jq
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing OpenClaw Framework"
$STD npm install --global openclaw
msg_ok "Installed OpenClaw"

msg_info "Installing gog (Google Workspace CLI & MCP)"
$STD curl -fsSL https://github.com/openclaw/gogcli/releases/latest/download/gog-linux-amd64 -o /usr/local/bin/gog
chmod +x /usr/local/bin/gog
msg_ok "Installed gog"

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
