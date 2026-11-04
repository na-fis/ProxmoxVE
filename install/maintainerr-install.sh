#!/usr/bin/env bash

# This script is used by both the initial ARR-Stack installation 
# and the catch-up upgrade process.

if ! command -v msg_info &>/dev/null; then
    msg_info() { echo -e "\e[34m[INFO]\e[0m $*"; }
    msg_ok() { echo -e "\e[32m[OK]\e[0m $*"; }
    msg_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }
fi
STD="${STD:-}"

function install_maintainerr() {
    # Ensure Node.js and Corepack are installed
    if ! command -v corepack &> /dev/null; then
        msg_info "Installing Node.js and Corepack"
        source <(curl -fsSL https://raw.githubusercontent.com/na-fis/ProxmoxVE/main/misc/tools.func)
        NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs
        msg_ok "Installed Node.js and Corepack"
    fi

    msg_info "Installing Maintainerr Dependencies"
    $STD apt-get update
    $STD apt-get install -y build-essential python3 pkg-config libcairo2-dev libpango1.0-dev libpixman-1-dev
    corepack enable
    msg_ok "Installed Maintainerr Dependencies"

    msg_info "Cloning and Building Maintainerr (Patience)"
    mkdir -p /var/lib/maintainerr/
    chmod 775 /var/lib/maintainerr/

    rm -rf /opt/maintainerr
    git clone https://github.com/Maintainerr/Maintainerr.git /opt/maintainerr
    ln -sfn /opt/maintainerr /opt/app

    cd /opt/maintainerr || exit
    $STD env CYPRESS_INSTALL_BINARY=0 yarn install --network-timeout 99999999
    $STD yarn turbo build

    cp -r /opt/maintainerr/apps/ui/dist /opt/maintainerr/apps/server/dist/ui
    msg_ok "Built Maintainerr"

    msg_info "Creating Maintainerr Service"
    cat <<EOF >/etc/systemd/system/maintainerr.service
[Unit]
Description=Maintainerr Service
After=network.target

[Service]
User=root
Group=root
UMask=0000
Type=exec
WorkingDirectory=/opt/maintainerr/apps/server
Environment=NODE_ENV=production
Environment=DATA_DIR=/var/lib/maintainerr
Environment=UI_PORT=6246
Environment=UI_HOSTNAME=0.0.0.0
ExecStart=/usr/bin/node dist/main
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q --now maintainerr.service
    msg_ok "Created Maintainerr Service"
}

# Run the installation
install_maintainerr
