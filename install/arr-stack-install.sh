#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: Combined Arr Stack (Sonarr + Radarr + Overseerr)

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    sqlite3 \
    git \
    build-essential
msg_ok "Installed Dependencies"

# Install Node.js for Overseerr
NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs

msg_info "Installing Sonarr v4"
mkdir -p /var/lib/sonarr/
chmod 775 /var/lib/sonarr/
curl -fsSL "https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=x64" -o "SonarrV4.tar.gz"
tar -xzf SonarrV4.tar.gz
mv Sonarr /opt
rm -rf SonarrV4.tar.gz
msg_ok "Installed Sonarr v4"

msg_info "Installing Radarr"
temp_file="$(mktemp)"
mkdir -p /var/lib/radarr/
chmod 775 /var/lib/radarr/
cd /var/lib/radarr/
RELEASE=$(curl -fsSL https://api.github.com/repos/Radarr/Radarr/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/Radarr/Radarr/releases/download/v${RELEASE}/Radarr.master.${RELEASE}.linux-core-x64.tar.gz" -o "$temp_file"
$STD tar -xvzf "$temp_file"
mv Radarr /opt
chmod 775 /opt/Radarr
rm -rf "$temp_file"
msg_ok "Installed Radarr"

msg_info "Installing Overseerr (Patience)"
mkdir -p /var/lib/overseerr/
chmod 775 /var/lib/overseerr/
fetch_and_deploy_gh_release "overseerr" "sct/overseerr"
cd /opt/overseerr
$STD yarn install
$STD yarn build
msg_ok "Installed Overseerr"

msg_info "Creating Sonarr Service"
cat <<EOF >/etc/systemd/system/sonarr.service
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target
[Service]
User=root
Group=root
UMask=0000
Type=simple
ExecStart=/opt/Sonarr/Sonarr -nobrowser -data=/var/lib/sonarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now sonarr
msg_ok "Created Sonarr Service"

msg_info "Creating Radarr Service"
cat <<EOF >/etc/systemd/system/radarr.service
[Unit]
Description=Radarr Daemon
After=syslog.target network.target
[Service]
User=root
Group=root
UMask=0000
Type=simple
ExecStart=/opt/Radarr/Radarr -nobrowser -data=/var/lib/radarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now radarr
msg_ok "Created Radarr Service"

msg_info "Creating Overseerr Service"
cat <<EOF >/etc/systemd/system/overseerr.service
[Unit]
Description=Overseerr Service
After=network.target

[Service]
User=root
Group=root
UMask=0000
Type=exec
WorkingDirectory=/opt/overseerr
Environment=CONFIG_DIRECTORY=/var/lib/overseerr
ExecStart=/usr/bin/yarn start

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now overseerr.service
msg_ok "Created Overseerr Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
