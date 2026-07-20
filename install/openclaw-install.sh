#!/usr/bin/env bash

# Copyright (c) 2021-2026 ProxmoxVE Community Scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.ai

export APPLICATION="${APPLICATION:-OpenClaw}"
export app="${app:-openclaw}"

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
if $STD npm install --global gogcli-mcp 2>/dev/null; then
  msg_ok "Installed gogcli-mcp"
else
  msg_warn "Could not install gogcli-mcp - skipping"
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
