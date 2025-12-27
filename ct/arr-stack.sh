#!/usr/bin/env bash
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/na-fis/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: Combined Arr Stack (Sonarr + Radarr + Overseerr)

APP="Arr-Stack"
var_tags="${var_tags:-arr,media}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    
    # Check if any of the applications are installed
    if [[ ! -d /var/lib/sonarr/ ]] && [[ ! -d /var/lib/radarr/ ]] && [[ ! -d /var/lib/overseerr/ ]] && [[ ! -d /var/lib/agregarr/ ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    
    # Update Sonarr if installed
    if [[ -d /var/lib/sonarr/ ]]; then
        msg_info "Updating Sonarr v4"
        systemctl stop sonarr.service
        curl -fsSL "https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=x64" -o "SonarrV4.tar.gz"
        tar -xzf SonarrV4.tar.gz
        rm -rf /opt/Sonarr
        mv Sonarr /opt
        rm -rf SonarrV4.tar.gz
        systemctl start sonarr.service
        msg_ok "Updated Sonarr v4"
    fi
    
    # Update Radarr if installed
    if [[ -d /var/lib/radarr/ ]]; then
        msg_info "Updating Radarr"
        systemctl stop radarr.service
        temp_file="$(mktemp)"
        rm -rf /opt/Radarr
        RELEASE=$(curl -fsSL https://api.github.com/repos/Radarr/Radarr/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
        curl -fsSL "https://github.com/Radarr/Radarr/releases/download/v${RELEASE}/Radarr.master.${RELEASE}.linux-core-x64.tar.gz" -o "$temp_file"
        $STD tar -xvzf "$temp_file"
        mv Radarr /opt
        chmod 775 /opt/Radarr
        rm -rf "$temp_file"
        systemctl start radarr.service
        msg_ok "Updated Radarr"
    fi
    
    # Update Overseerr if installed
    if [[ -d /var/lib/overseerr/ ]]; then
        msg_info "Updating Overseerr"
        systemctl stop overseerr.service

        # Get current version
        CURRENT_VERSION=""
        if [[ -f ~/.overseerr ]]; then
            CURRENT_VERSION=$(cat ~/.overseerr)
        fi

        # Get latest release version
        RELEASE=$(curl -fsSL https://api.github.com/repos/sct/overseerr/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

        if [[ "${RELEASE}" != "${CURRENT_VERSION}" ]]; then
            # Backup current installation
            rm -rf /opt/overseerr_backup
            cp -r /opt/overseerr /opt/overseerr_backup

            # Download and install new version
            rm -rf /opt/overseerr
            fetch_and_deploy_gh_release "overseerr" "sct/overseerr"
            cd /opt/overseerr || exit
            $STD CYPRESS_INSTALL_BINARY=0 yarn install
            $STD yarn build

            # Save version
            echo "${RELEASE}" > ~/.overseerr
            msg_ok "Updated Overseerr to v${RELEASE}"
        else
            msg_ok "Overseerr is already up to date (v${RELEASE})"
        fi

        systemctl start overseerr.service
    fi

    # Update or Install Agregarr
    if [[ -d /opt/agregarr ]]; then
        msg_info "Updating Agregarr"
        systemctl stop agregarr.service
        cd /opt/agregarr || exit
        git pull
        $STD CYPRESS_INSTALL_BINARY=0 yarn install
        $STD yarn build
        systemctl start agregarr.service
        msg_ok "Updated Agregarr"
    else
        msg_info "Installing Agregarr (New Component)"
        # shellcheck disable=SC1090
        source <(curl -s https://raw.githubusercontent.com/na-fis/ProxmoxVE/main/install/agregarr-install.sh)
    fi
    
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the applications using the following URLs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Sonarr: http://${IP}:8989${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Radarr: http://${IP}:7878${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Overseerr: http://${IP}:5055${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Agregarr: http://${IP}:7171${CL}"
