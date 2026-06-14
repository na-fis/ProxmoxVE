#!/bin/bash
# Proxmox VE & LXC Containers Changes Rollback Script
# This script reverts all modifications made by the AI assistant.

echo "=== STARTING ROLLBACK ON PROXMOX HOST ==="

# 1. Remove GITHUB_TOKEN from host environment files
if [ -f /etc/environment ]; then
  echo "Removing GITHUB_TOKEN from /etc/environment..."
  sed -i '/GITHUB_TOKEN=/d' /etc/environment
fi

if [ -f /root/.bashrc ]; then
  echo "Removing GITHUB_TOKEN from /root/.bashrc..."
  sed -i '/GITHUB_TOKEN/d' /root/.bashrc
fi

# 2. Clean up any host curlrc files
rm -f /root/.curlrc

# 3. Rollback changes inside all LXC containers
for vmid in $(pct list | awk '{if(NR>1) print $1}'); do
  echo "Reverting changes in LXC $vmid..."
  
  # Remove the curl wrapper (both old /usr/local/bin and diverted /usr/bin)
  pct exec $vmid -- rm -f /usr/local/bin/curl
  if pct exec $vmid -- dpkg-divert --list '/usr/bin/curl' | grep -q 'curl.real'; then
    pct exec $vmid -- rm -f /usr/bin/curl
    pct exec $vmid -- dpkg-divert --remove --rename --divert /usr/bin/curl.real /usr/bin/curl
  fi
  
  # Remove curlrc configurations
  pct exec $vmid -- rm -f /root/.curlrc /etc/curlrc
  
  # Restore original /bin/update and /usr/bin/update if they were wrapped
  for update_path in /bin/update /usr/bin/update; do
    if pct exec $vmid -- test -f "$update_path"; then
      if pct exec $vmid -- grep -q "Automatically generated update wrapper" "$update_path"; then
        orig_cmd=$(pct exec $vmid -- tail -n 1 "$update_path")
        if echo "$orig_cmd" | grep -q "bash -c"; then
          echo "Restoring original $update_path in LXC $vmid..."
          pct exec $vmid -- sh -c "echo '$orig_cmd' > $update_path"
          pct exec $vmid -- chmod 755 "$update_path"
        fi
      fi
    fi
  done

  # Remove GITHUB_TOKEN from container environment files
  pct exec $vmid -- sh -c '
    if [ -f /etc/environment ]; then
      sed -i "/GITHUB_TOKEN=/d" /etc/environment
    fi
    if [ -f /root/.bashrc ]; then
      sed -i "/GITHUB_TOKEN/d" /root/.bashrc
    fi
  '
done

echo "=== ROLLBACK COMPLETED SUCCESSFULLY ==="
