#!/usr/bin/env bash
# ==============================================================================
# Automated Unattended Update Script for Proxmox VE LXCs and VMs
# ==============================================================================

set -u

echo "=========================================================="
echo " Starting Proxmox LXC & VM Update Sweep: $(date)"
echo "=========================================================="

# ------------------------------------------------------------------------------
# 1. Update LXC Containers
# ------------------------------------------------------------------------------
for vmid in $(pct list | awk 'NR>1 {print $1}'); do
    name=$(pct exec "$vmid" hostname 2>/dev/null || pct config "$vmid" | awk '/^hostname:/ {print $2}')
    status=$(pct status "$vmid")

    if [ "$status" != "status: running" ]; then
        echo -e "\n[LXC $vmid - $name] Skipping (Not running)"
        continue
    fi

    # Check if container is a template
    if pct config "$vmid" | grep -q "^template:"; then
        echo -e "\n[LXC $vmid - $name] Skipping (Template)"
        continue
    fi

    echo -e "\n=========================================================="
    echo " Updating LXC $vmid ($name)"
    echo "=========================================================="

    # Case A: Container has Community-Scripts built-in 'update' command
    if pct exec "$vmid" -- which update >/dev/null 2>&1; then
        echo "Found Community-Scripts updater. Running silent update..."
        pct exec "$vmid" -- env PHS_SILENT=1 DEBIAN_FRONTEND=noninteractive bash -c update </dev/null
    
    # Case B: Container does NOT have built-in update command (Fallback to Native Package Manager)
    else
        ostype=$(pct config "$vmid" | awk '/^ostype:/ {print $2}')
        echo "No built-in update script found. Updating via native package manager ($ostype)..."

        case "$ostype" in
            ubuntu|debian|devuan)
                pct exec "$vmid" -- env DEBIAN_FRONTEND=noninteractive bash -c \
                    "apt-get update && apt-get -yq -o Dpkg::Options::='--force-confold' -o Dpkg::Options::='--force-confdef' dist-upgrade && apt-get -yq autoremove && apt-get -yq autoclean" </dev/null
                ;;
            alpine)
                pct exec "$vmid" -- ash -c "apk update && apk upgrade" </dev/null
                ;;
            archlinux)
                pct exec "$vmid" -- bash -c "pacman -Syu --noconfirm" </dev/null
                ;;
            fedora|rocky|centos|alma)
                pct exec "$vmid" -- bash -c "dnf -y update && dnf -y upgrade" </dev/null
                ;;
            opensuse)
                pct exec "$vmid" -- bash -c "zypper ref && zypper --non-interactive dup" </dev/null
                ;;
            *)
                echo "Unknown or unsupported OS type ($ostype). Skipping."
                ;;
        esac
    fi

    echo "Done with LXC $vmid."
done

# ------------------------------------------------------------------------------
# 2. Update Virtual Machines (VMs)
# ------------------------------------------------------------------------------
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    name=$(qm list | awk -v id="$vmid" '$1 == id {print $2}')
    status=$(qm status "$vmid")

    if [ "$status" != "status: running" ]; then
        echo -e "\n[VM $vmid - $name] Skipping (Not running)"
        continue
    fi

    echo -e "\n=========================================================="
    echo " Checking VM $vmid ($name)"
    echo "=========================================================="

    # Check if QEMU Guest Agent is installed and running
    if ! qm agent "$vmid" ping >/dev/null 2>&1; then
        echo "QEMU Guest Agent not responding on VM $vmid. Skipping automated updates."
        continue
    fi

    # Special Case: Home Assistant OS VM (e.g. VMID 105)
    if [ "$name" = "homeassistant" ] || [ "$vmid" -eq 105 ]; then
        echo "Detected Home Assistant OS VM. Checking available updates..."
        qm guest exec "$vmid" -- ha available-updates
        echo "Note: To apply HA updates automatically, trigger 'ha core update' / 'ha os update' via HA CLI or UI."
    
    # Generic Linux VM with Guest Agent
    else
        echo "Running non-interactive update via QEMU Guest Agent..."
        qm guest exec "$vmid" -- /bin/bash -c \
            "DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade" </dev/null 2>&1 || true
    fi

    echo "Done with VM $vmid."
done

echo -e "\n=========================================================="
echo " All updates completed."
echo "=========================================================="
