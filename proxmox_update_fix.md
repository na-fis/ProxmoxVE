# Proxmox VE Helper-Scripts Update Fix

This document outlines the troubleshooting steps, root cause analysis, and implementation details of the fix deployed to resolve the update failures across the LXC containers on the Proxmox VE host (`nafbox`).

---

## 1. Symptoms & Initial Context

When attempting to run the built-in `update` command inside various LXC containers created using the Proxmox Helper-Scripts, the process aborted with errors like:
* `GitHub API authentication failed (HTTP 401)`
* `Could not fetch latest uv version from GitHub API`
* `exit code 7 (curl: Failed to connect (network unreachable / host down))`

---

## 2. Root Cause Analysis

We identified three compounding issues that caused these failures:

### A. IP-Level GitHub API Rate Limiting (HTTP 403)
The homelab's public IP address (`71.198.94.20`) exceeded GitHub's anonymous API limit of **60 requests per hour**. This was caused by multiple containers aggressively querying the GitHub API to check for updates. Once rate-limited, all unauthenticated requests to `api.github.com` failed.

### B. Duplicate Header Conflict (HTTP 401)
To supply a Personal Access Token (PAT) globally, we initially configured `/root/.curlrc` to automatically inject the token. However, some authenticated functions inside the helper scripts (`tools.func`) *already* explicitly append the `Authorization` header. Sending the header twice caused GitHub to reject the requests with a `401 Unauthorized` error.

### C. Unauthenticated Script Calls
Some functions in the helper scripts (specifically `setup_uv` which installs/upgrades Python's package manager `uv`) make raw, unauthenticated `curl` requests to the GitHub API, completely ignoring the `GITHUB_TOKEN` environment variable. When your IP is rate-limited, these unauthenticated requests instantly fail (exit code `7` or `22`), causing the entire container update process to abort.

---

## 3. The Solution: In-Memory Script-Level Curl Wrapper

To bypass these limitations without modifying the official helper scripts (which are downloaded dynamically from GitHub during every update), and without modifying the system's core binaries (which can cause issues during package upgrades), we implemented an **In-Memory Script-Level Curl Wrapper**.

### A. Deploying the Wrapper
Instead of renaming the system's `curl` binary using `dpkg-divert`, we wrap the `/bin/update` (and `/usr/bin/update`) entry point scripts inside each container. When the user or host executes `update`, the wrapper script runs first, which:
1. **Loads `GITHUB_TOKEN`:** Sourced from the container's `/etc/environment`.
2. **Defines and Exports a `curl` bash function:** It intercepts any `curl` calls made by the update script (and any child bash scripts it invokes).
3. **Executes the original update command:** Inherits the exported function.

#### Wrapper Script Logic (`/bin/update`):
```bash
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
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/sabnzbd.sh)"
```

### B. Token Configuration
We configured the environment variables on the Proxmox host and within all containers:
* **`/etc/environment`**: Appended `GITHUB_TOKEN="ghp_UZzAkvhj..."` to preserve the token.
* **`/root/.bashrc`**: Appended `export GITHUB_TOKEN="ghp_UZzAkvhj..."` for interactive shells.

---

## 4. Outcome & Container Verification

After executing the configuration script, we ran updates across all running containers with the following results:

* **`100` (plex)**: Succeeded. Up to date.
* **`101` (sabnzbd)**: Succeeded. Successfully updated SABnzbd from `5.0.1` to `5.0.3` (building dependency python package using the newly installed `uv` 0.11.16).
* **`102` (arr-stack)**: Succeeded. Sonarr, Radarr, Bazarr, Prowlarr, and Recyclarr are all up to date.
* **`103` (pihole)**: Succeeded. Updated successfully.
* **`104` (traefik)**: Succeeded. Successfully updated Traefik from `3.6.8` to `3.7.1`.
* **`106` (nextcloudpi)**: Succeeded. Updated successfully.

### Note on VMID `105` (`n8n`):
The update for `n8n` failed because the container is currently under-provisioned:
* **Required resources**: At least 2 Cores and 2048 MB RAM.
* **Current resources**: 1 Core and 2048 MB RAM.
* **Fix**: Shut down the container, go to Proxmox Web GUI -> `n8n` container -> **Resources**, change **Cores** to **2**, start the container, and run `update`.

---

## 5. How to Undo All Changes (Rollback Plan)

If you ever want to completely revert all modifications made to your Proxmox VE host and its containers, we have created an automated rollback script at `undo_proxmox_changes.sh` in this directory.

### To execute the rollback:
1. Copy the `undo_proxmox_changes.sh` script to your Proxmox host `/tmp` directory:
   ```powershell
   scp C:\Users\d1xlo\work\ProxmoxVE\undo_proxmox_changes.sh root@192.168.50.164:/tmp/undo_proxmox_changes.sh
   ```
2. Log into your Proxmox host shell and execute the script:
   ```bash
   bash /tmp/undo_proxmox_changes.sh
   ```

### What the rollback script does:
1. **Host Environment Cleanup:** Removes the `GITHUB_TOKEN` from `/etc/environment` and `/root/.bashrc` on the host.
2. **Container Cleanup:** Iterates through all LXC containers and deletes `/usr/local/bin/curl` (the wrapper), `/root/.curlrc`, and `/etc/curlrc` (if present), and removes the `GITHUB_TOKEN` from container environments.
