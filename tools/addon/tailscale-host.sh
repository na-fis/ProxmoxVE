#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
  ______      _ __                __
 /_  __/___ _(_) /_____________ _/ /__
  / / / __ `/ / / ___/ ___/ __ `/ / _ \
 / / / /_/ / / (__  ) /__/ /_/ / /  __/
/_/  \__,_/_/_/____/\___/\__,_/_/\___/
                    Host Installation
EOF
}

# Standard color definitions and functions
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
silent() { "$@" >/dev/null 2>&1; }
set -e

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function check_tailscale_installed() {
  if command -v tailscale >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

function get_tailscale_version() {
  if check_tailscale_installed; then
    tailscale version | head -n1 | awk '{print $1}'
  else
    echo "Not installed"
  fi
}

install() {
  header_info

  if check_tailscale_installed; then
    msg_error "Tailscale is already installed. Use 'Upgrade' option to update."
    echo ""
    echo "Current version: $(get_tailscale_version)"
    echo "Press any key to continue..."
    read -n 1
    return
  fi

  while true; do
    read -r -p "Install Tailscale on Proxmox VE host? This will allow remote access to your Proxmox server. Proceed(y/n)?" yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  # Configuration options
  header_info
  echo "Configuration Options:"
  echo ""

  # Auth key prompt
  read -r -p "Enter Tailscale auth key (optional, press Enter to skip): " AUTH_KEY

  # Subnet router option
  read -r -p "Configure as subnet router? This allows access to local network through Tailscale <y/N> " SUBNET_ROUTER
  if [[ ${SUBNET_ROUTER,,} =~ ^(y|yes)$ ]]; then
    read -r -p "Enter subnet to advertise (e.g., 192.168.1.0/24): " ADVERTISE_ROUTES
  fi

  # Exit node option
  read -r -p "Configure as exit node? This routes internet traffic through this host <y/N> " EXIT_NODE

  # Verbose mode
  read -r -p "Verbose mode? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    STD=""
  else
    STD="silent"
  fi

  header_info

  msg_info "Installing Tailscale repository"
  ID=$(grep "^ID=" /etc/os-release | cut -d"=" -f2)
  VER=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d"=" -f2)
  curl -fsSL https://pkgs.tailscale.com/stable/"$ID"/"$VER".noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/$ID $VER main" >/etc/apt/sources.list.d/tailscale.list
  msg_ok "Installed Tailscale repository"

  msg_info "Installing Tailscale"
  $STD apt-get update
  $STD apt-get install -y tailscale
  msg_ok "Installed Tailscale"

  configure_tailscale "$AUTH_KEY" "$SUBNET_ROUTER" "$ADVERTISE_ROUTES" "$EXIT_NODE"

  msg_ok "Completed Successfully!\n"

  if [ -z "$AUTH_KEY" ]; then
    echo -e "\n${YW}To complete setup, run: ${BL}tailscale up${CL}"
    echo -e "${YW}Then visit the provided URL to authenticate${CL}\n"
  fi

  echo -e "${YW}Tailscale Status: ${BL}tailscale status${CL}"
  echo -e "${YW}Configuration files: ${BL}/etc/tailscale/${CL}"
  echo -e "${YW}Installed version: ${BL}$(get_tailscale_version)${CL}\n"
}

configure_tailscale() {
  local AUTH_KEY="$1"
  local SUBNET_ROUTER="$2"
  local ADVERTISE_ROUTES="$3"
  local EXIT_NODE="$4"

  msg_info "Configuring Tailscale"

  # Enable IP forwarding if subnet router or exit node
  if [[ ${SUBNET_ROUTER,,} =~ ^(y|yes)$ ]] || [[ ${EXIT_NODE,,} =~ ^(y|yes)$ ]]; then
    echo 'net.ipv4.ip_forward = 1' >>/etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >>/etc/sysctl.conf
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
  fi

  # Create configuration directory
  mkdir -p /etc/tailscale

  # Create startup script
  cat >/etc/tailscale/startup.sh <<'EOF'
#!/bin/bash
# Tailscale startup configuration
# This script is run when Tailscale starts

# Wait for tailscaled to be ready
sleep 5

# Check if already connected
if ! tailscale status >/dev/null 2>&1; then
    # Build tailscale up command
    UP_CMD="tailscale up"
    
    # Add auth key if provided
    if [ -f /etc/tailscale/authkey ]; then
        UP_CMD="$UP_CMD --authkey=$(cat /etc/tailscale/authkey)"
    fi
    
    # Add advertise routes if configured
    if [ -f /etc/tailscale/advertise-routes ]; then
        UP_CMD="$UP_CMD --advertise-routes=$(cat /etc/tailscale/advertise-routes)"
    fi
    
    # Add exit node if configured
    if [ -f /etc/tailscale/exit-node ]; then
        UP_CMD="$UP_CMD --advertise-exit-node"
    fi
    
    # Execute the command
    eval $UP_CMD
fi
EOF
  chmod +x /etc/tailscale/startup.sh

  # Save configuration
  if [ -n "$AUTH_KEY" ]; then
    echo "$AUTH_KEY" >/etc/tailscale/authkey
    chmod 600 /etc/tailscale/authkey
  fi

  if [[ ${SUBNET_ROUTER,,} =~ ^(y|yes)$ ]] && [ -n "$ADVERTISE_ROUTES" ]; then
    echo "$ADVERTISE_ROUTES" >/etc/tailscale/advertise-routes
  fi

  if [[ ${EXIT_NODE,,} =~ ^(y|yes)$ ]]; then
    touch /etc/tailscale/exit-node
  fi

  # Create systemd service for auto-configuration
  cat >/etc/systemd/system/tailscale-config.service <<'EOF'
[Unit]
Description=Tailscale Configuration
After=tailscaled.service
Wants=tailscaled.service

[Service]
Type=oneshot
ExecStart=/etc/tailscale/startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable tailscaled
  systemctl enable tailscale-config
  systemctl start tailscaled

  # Start Tailscale if auth key provided
  if [ -n "$AUTH_KEY" ]; then
    msg_info "Connecting to Tailscale network"
    systemctl start tailscale-config
    msg_ok "Connected to Tailscale network"
  fi

  msg_ok "Configured Tailscale"
}

upgrade() {
  header_info

  if ! check_tailscale_installed; then
    msg_error "Tailscale is not installed. Use 'Install' option first."
    echo "Press any key to continue..."
    read -n 1
    return
  fi

  CURRENT_VERSION=$(get_tailscale_version)
  echo "Current Tailscale version: $CURRENT_VERSION"
  echo ""

  while true; do
    read -r -p "Upgrade Tailscale to the latest version? Proceed(y/n)?" yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  read -r -p "Verbose mode? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    STD=""
  else
    STD="silent"
  fi

  header_info

  msg_info "Updating package repositories"
  $STD apt-get update
  msg_ok "Updated package repositories"

  msg_info "Upgrading Tailscale"
  $STD apt-get install -y --only-upgrade tailscale
  msg_ok "Upgraded Tailscale"

  msg_info "Restarting Tailscale services"
  systemctl restart tailscaled
  systemctl restart tailscale-config 2>/dev/null || true
  msg_ok "Restarted Tailscale services"

  NEW_VERSION=$(get_tailscale_version)

  msg_ok "Completed Successfully!\n"
  echo -e "${YW}Previous version: ${BL}$CURRENT_VERSION${CL}"
  echo -e "${YW}Current version: ${BL}$NEW_VERSION${CL}"

  if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo -e "${GN}Tailscale has been upgraded successfully!${CL}\n"
  else
    echo -e "${YW}Tailscale was already at the latest version.${CL}\n"
  fi
}

uninstall() {
  header_info

  if ! check_tailscale_installed; then
    msg_error "Tailscale is not installed."
    echo "Press any key to continue..."
    read -r -n 1
    return
  fi

  while true; do
    read -r -p "This will remove Tailscale from the Proxmox VE host. Proceed(y/n)?" yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  read -r -p "Verbose mode? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    STD=""
  else
    STD="silent"
  fi
  header_info

  msg_info "Disconnecting from Tailscale"
  tailscale down 2>/dev/null || true
  msg_ok "Disconnected from Tailscale"

  msg_info "Uninstalling Tailscale"
  systemctl stop tailscale-config 2>/dev/null || true
  systemctl stop tailscaled 2>/dev/null || true
  systemctl disable tailscale-config 2>/dev/null || true
  systemctl disable tailscaled 2>/dev/null || true

  rm -f /etc/systemd/system/tailscale-config.service
  rm -rf /etc/tailscale
  rm -f /etc/apt/sources.list.d/tailscale.list
  rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg

  $STD apt-get remove --purge -y tailscale
  systemctl daemon-reload
  $STD apt autoremove -y
  msg_ok "Uninstalled Tailscale"

  msg_ok "Completed Successfully!\n"
}

show_status() {
  header_info

  if ! check_tailscale_installed; then
    echo -e "${RD}Tailscale is not installed.${CL}\n"
    echo "Press any key to continue..."
    read -r -n 1
    return
  fi

  echo "Tailscale Status:"
  echo "=================="
  echo ""

  # Show version
  echo -e "${YW}Version:${CL} $(get_tailscale_version)"
  echo ""

  # Show connection status
  if tailscale status >/dev/null 2>&1; then
    echo -e "${GN}Status: Connected${CL}"
    echo ""
    tailscale status
  else
    echo -e "${RD}Status: Not connected${CL}"
    echo ""
    echo "Run 'tailscale up' to connect to your Tailscale network"
  fi

  echo ""
  echo "Configuration files: /etc/tailscale/"

  # Show configuration
  if [ -f /etc/tailscale/advertise-routes ]; then
    echo -e "${YW}Subnet Router:${CL} $(cat /etc/tailscale/advertise-routes)"
  fi

  if [ -f /etc/tailscale/exit-node ]; then
    echo -e "${YW}Exit Node:${CL} Enabled"
  fi

  echo ""
  echo "Press any key to continue..."
  read -r -n 1
}

reconfigure() {
  header_info

  if ! check_tailscale_installed; then
    msg_error "Tailscale is not installed. Use 'Install' option first."
    echo "Press any key to continue..."
    read -r -n 1
    return
  fi

  echo "Reconfigure Tailscale Settings:"
  echo "==============================="
  echo ""

  # Show current configuration
  echo "Current Configuration:"
  if [ -f /etc/tailscale/advertise-routes ]; then
    echo "  Subnet Router: $(cat /etc/tailscale/advertise-routes)"
  else
    echo "  Subnet Router: Disabled"
  fi

  if [ -f /etc/tailscale/exit-node ]; then
    echo "  Exit Node: Enabled"
  else
    echo "  Exit Node: Disabled"
  fi
  echo ""

  while true; do
    read -r -p "Proceed with reconfiguration? (y/n)?" yn
    case $yn in
    [Yy]*) break ;;
    [Nn]*) exit ;;
    *) echo "Please answer yes or no." ;;
    esac
  done

  # New configuration options
  read -r -p "Enter new Tailscale auth key (optional, press Enter to skip): " AUTH_KEY

  read -r -p "Configure as subnet router? <y/N> " SUBNET_ROUTER
  if [[ ${SUBNET_ROUTER,,} =~ ^(y|yes)$ ]]; then
    read -r -p "Enter subnet to advertise (e.g., 192.168.1.0/24): " ADVERTISE_ROUTES
  fi

  read -r -p "Configure as exit node? <y/N> " EXIT_NODE

  header_info

  msg_info "Disconnecting from Tailscale"
  tailscale down 2>/dev/null || true
  msg_ok "Disconnected from Tailscale"

  # Remove old configuration
  rm -f /etc/tailscale/authkey
  rm -f /etc/tailscale/advertise-routes
  rm -f /etc/tailscale/exit-node

  configure_tailscale "$AUTH_KEY" "$SUBNET_ROUTER" "$ADVERTISE_ROUTES" "$EXIT_NODE"

  msg_ok "Reconfiguration completed!\n"

  if [ -z "$AUTH_KEY" ]; then
    echo -e "\n${YW}To complete setup, run: ${BL}tailscale up${CL}"
    echo -e "${YW}Then visit the provided URL to authenticate${CL}\n"
  fi
}

# Version check
if ! pveversion | grep -Eq "pve-manager/8\.[0-4](\.[0-9]+)*"; then
  echo -e "This version of Proxmox Virtual Environment is not supported"
  echo -e "Requires PVE Version 8.0 or higher"
  echo -e "Exiting..."
  sleep 2
  exit
fi

# Main menu
OPTIONS=(Install "Install Tailscale on Proxmox VE Host"
  Upgrade "Upgrade Tailscale to Latest Version"
  Uninstall "Uninstall Tailscale from Proxmox VE Host"
  Status "Show Tailscale Status and Configuration"
  Reconfigure "Reconfigure Tailscale Settings")

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Tailscale Host Addon" --menu "Select an option:" 14 70 5 \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

case $CHOICE in
"Install")
  install
  ;;
"Upgrade")
  upgrade
  ;;
"Uninstall")
  uninstall
  ;;
"Status")
  show_status
  ;;
"Reconfigure")
  reconfigure
  ;;
*)
  echo "Exiting..."
  exit 0
  ;;
esac
