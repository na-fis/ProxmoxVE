#!/usr/bin/env bash

# Copyright (c) 2021-2026 ProxmoxVE Community Scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://hermes-agent.nousresearch.com/

set +u

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



msg_info "Creating Hermes User"
useradd -m -s /bin/bash hermes
loginctl enable-linger hermes
echo 'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"' >>/home/hermes/.profile
msg_ok "Created Hermes User"

msg_info "Configuring Service Environment"
cat <<EOF >/etc/default/hermes
HOME=/home/hermes
PATH=/home/hermes/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NODE_OPTIONS=${NODE_OPTIONS}
EOF
msg_ok "Configured Service Environment"



msg_info "Installing Hermes Agent"
$STD setsid --wait bash -c '
  set -a; source /etc/default/hermes; set +a
  export npm_config_yes=true
  bash <(curl -fsSL https://hermes-agent.nousresearch.com/install.sh) --skip-setup
'
msg_ok "Installed Hermes Agent"

msg_info "Configuring systemd service"
mkdir -p /home/hermes/.config/systemd/user
cat <<EOF >/home/hermes/.config/systemd/user/hermes.service
[Unit]
Description=Hermes AI Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/hermes
EnvironmentFile=/etc/default/hermes
ExecStart=/usr/local/bin/hermes gateway run
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

chown -R hermes:hermes /home/hermes/.config
sudo -u hermes -i systemctl --user daemon-reload
sudo -u hermes -i systemctl --user enable hermes.service
msg_ok "Configured systemd service"

motd_ssh
customize
cleanup_lxc
