#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/na-fis/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 ProxmoxVE Community Scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.ai

APP="OpenClaw"
var_tags="${var_tags:-automation,ai}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/openclaw.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  NODE_VERSION="22" setup_nodejs
  msg_info "Updating ${APP} LXC"
  $STD npm install -g openclaw@latest
  $STD curl -fsSL https://github.com/openclaw/gogcli/releases/latest/download/gog-linux-amd64 -o /usr/local/bin/gog
  chmod +x /usr/local/bin/gog
  systemctl restart openclaw
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
