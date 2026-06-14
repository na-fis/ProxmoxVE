#!/bin/bash
# Proxmox VE & LXC Containers Smart Update Wrapper Setup
# This script configures the GITHUB_TOKEN and wraps the update command safely.

# Read token from argument, environment, or existing host environment
TOKEN="$1"
if [ -z "$TOKEN" ]; then
  TOKEN="$GITHUB_TOKEN"
fi

if [ -z "$TOKEN" ]; then
  if [ -f /etc/environment ]; then
    # Extract token value and strip quotes
    val=$(grep "GITHUB_TOKEN=" /etc/environment | cut -d'=' -f2-)
    val="${val#\"}"
    val="${val%\"}"
    TOKEN="$val"
  fi
fi

if [ -z "$TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set."
  echo "Usage: $0 <github_token>"
  echo "Or set the GITHUB_TOKEN environment variable."
  exit 1
fi

echo "=== STARTING CONFIGURATION ON PROXMOX HOST ==="

# 1. Configure GITHUB_TOKEN on host
if [ -f /etc/environment ]; then
  if ! grep -q "GITHUB_TOKEN=" /etc/environment; then
    echo "Adding GITHUB_TOKEN to /etc/environment on host..."
    echo "GITHUB_TOKEN=\"$TOKEN\"" >> /etc/environment
  else
    echo "Updating GITHUB_TOKEN in /etc/environment on host..."
    sed -i "s|GITHUB_TOKEN=.*|GITHUB_TOKEN=\"$TOKEN\"|g" /etc/environment
  fi
fi

if [ -f /root/.bashrc ]; then
  if ! grep -q "GITHUB_TOKEN" /root/.bashrc; then
    echo "Adding GITHUB_TOKEN to /root/.bashrc on host..."
    echo "export GITHUB_TOKEN=\"$TOKEN\"" >> /root/.bashrc
  fi
fi

# 2. Iterate through all running LXC containers
for vmid in $(pct list | awk '{if(NR>1) print $1}'); do
  status=$(pct status $vmid)
  if [ "$status" != "status: running" ]; then
    echo "LXC $vmid is not running, skipping."
    continue
  fi

  echo "Configuring LXC $vmid..."

  # A. Set GITHUB_TOKEN in container's /etc/environment
  pct exec $vmid -- sh -c "
    if [ -f /etc/environment ]; then
      if ! grep -q 'GITHUB_TOKEN=' /etc/environment; then
        echo 'GITHUB_TOKEN=\"$TOKEN\"' >> /etc/environment
      else
        sed -i 's|GITHUB_TOKEN=.*|GITHUB_TOKEN=\"$TOKEN\"|g' /etc/environment
      fi
    fi
  "

  # B. Patch /bin/update script
  orig_cmd=$(pct exec $vmid -- cat /bin/update 2>/dev/null)
  
  if [ -z "$orig_cmd" ]; then
    echo "LXC $vmid does not have /bin/update, skipping."
    continue
  fi

  # Check if already patched
  if echo "$orig_cmd" | grep -q "curl()"; then
    echo "LXC $vmid /bin/update is already patched."
    continue
  fi

  # Strip any leading shebang or comment lines
  clean_orig_cmd=$(echo "$orig_cmd" | grep -v "^#")

  echo "Patching /bin/update inside LXC $vmid..."
  
  # Write the wrapped script to /bin/update inside the container
  cat << 'EOF' > /tmp/wrapped_update
#!/bin/bash
# Automatically generated update wrapper to handle GITHUB_TOKEN and bypass rate limits safely.

# 1. Load GITHUB_TOKEN from /etc/environment if present
if [ -f /etc/environment ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    if [[ "$line" =~ ^GITHUB_TOKEN= ]]; then
      val="${line#*=}"
      val="${val#\"}"
      val="${val%\"}"
      export GITHUB_TOKEN="$val"
    fi
  done < /etc/environment
fi

# 2. Define curl wrapper function
curl() {
  local args=()
  local is_github=false
  local has_auth=false
  for arg in "$@"; do
    if [[ "$arg" == *"github.com"* ]] || [[ "$arg" == *"githubusercontent.com"* ]]; then
      is_github=true
    fi
    if [[ "$arg" == *"Authorization:"* ]] || [[ "$arg" == *"authorization:"* ]]; then
      has_auth=true
    fi
  done
  if [[ "$is_github" == "true" ]] && [[ "$has_auth" == "false" ]] && [[ -n "${GITHUB_TOKEN:-}" ]]; then
    command curl -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
  else
    command curl "$@"
  fi
}
export -f curl

# 3. Execute the original update command
EOF

  echo "$clean_orig_cmd" >> /tmp/wrapped_update
  
  # Push the file to the container
  pct push $vmid /tmp/wrapped_update /bin/update --perms 755
  
  # Also check if /usr/bin/update is a separate file
  if pct exec $vmid -- test -f /usr/bin/update; then
    if ! pct exec $vmid -- test -L /usr/bin/update; then
      pct push $vmid /tmp/wrapped_update /usr/bin/update --perms 755
    fi
  fi
  
  rm -f /tmp/wrapped_update
done

echo "=== CONFIGURATION COMPLETED SUCCESSFULLY ==="
