#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://seerr.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NODE_VERSION="22" NODE_MODULE="pnpm@latest" setup_nodejs
msg_info "Cloning and Building Seerr (Patience)"
git clone -b develop https://github.com/seerr-team/seerr.git /opt/seerr
cd /opt/seerr || exit
$STD pnpm install
$STD pnpm build
msg_ok "Configured Seerr"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/seerr.service
[Unit]
Description=Seerr Service
After=network.target

[Service]
Type=exec
WorkingDirectory=/opt/seerr
ExecStart=/usr/local/bin/pnpm start

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now seerr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
