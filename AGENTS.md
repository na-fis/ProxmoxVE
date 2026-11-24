# Proxmox VE Cluster & Agent Environment Memory

This repository contains tools, helper scripts, and automation workflows for managing the Proxmox VE homelab cluster.

---

## 1. Cluster Topology & Node Mapping

* **Proxmox VE Host**: `192.168.50.164` (Hostname: `nafbox`)
  * Gateway: `192.168.50.1`
  * Main Bridge: `vmbr0`
  * Local Storage Pools: `local` (Directory, ISOs/templates), `local-lvm` (LVM-Thin, VM/LXC disks)

| VMID | Name | IP Address | Description / Services |
| :--- | :--- | :--- | :--- |
| **107** | **antigravity** | `192.168.50.178` | **AI Agent & Remote Server Node** (Ubuntu 24.04 LTS, 4 vCPUs, 8GB RAM, 30GB disk). Runs Orca headless server (`orca-server.service` on port 6768) and Antigravity CLI (`agy`). |
| **100** | **nafbox-plex** | LAN | Plex Media Server |
| **101** | **sabnzbd** | LAN | Usenet download client |
| **102** | **arr-stack** | `10.10.10.243` | Media management suite (Sonarr, Radarr, Prowlarr, etc.) |
| **103** | **pihole** | `192.168.50.244` | Network DNS sinkhole & ad blocker |
| **104** | **traefik** | `192.168.50.240` | Reverse proxy and edge SSL termination |
| **106** | **nextcloudpi** | LAN | Nextcloud instance |

---

## 2. Host Control Bridge (`pve`)

From inside the **Agent LXC (VMID 107)**, passwordless SSH keys are pre-configured to the Proxmox host (`192.168.50.164`). 

Agents can run cluster operations directly using the `pve` wrapper:

```bash
# List all containers and VMs
pve pct list
pve qm list

# Execute commands inside ANY container across the cluster
pve pct exec <vmid> -- <command>
# Example: Check Pi-hole status
pve pct exec 103 -- pihole status

# Provision new containers
pve pct create <vmid> local:vztmpl/<template>.tar.zst --cores 2 --memory 2048 ...

# Container power lifecycle
pve pct start <vmid>
pve pct stop <vmid>
pve pct reboot <vmid>
pve pct destroy <vmid>

# Host storage & resource queries
pve pvesm status
pve free -h
```

---

## 3. Services Running on Agent Node (LXC 107)

* **Orca Runtime Server**:
  * Status: Managed via `systemd` unit `orca-server.service`
  * Port: `6768` (WebSocket endpoint: `ws://192.168.50.178:6768`, Web UI: `http://192.168.50.178:6768/web-index.html`)
  * CLI Wrapper: `/usr/local/bin/orca`
* **Antigravity CLI**:
  * Binary: `/usr/local/bin/agy` (v1.5.5)
* **Workspace Directory**:
  * Path: `~/work/ProxmoxVE` (cloned from `https://github.com/na-fis/ProxmoxVE.git`, upstream `community-scripts/ProxmoxVE`)

---

## 4. Key Documentation & Engineering Plans

* **`proxmox_update_fix.md`**: Architectural breakdown of the in-memory curl wrapper deployed across containers to resolve GitHub API rate-limiting issues when running container update scripts.
* **`HDD_SPINDOWN.md`**: Guide for hard drive spindown and power management on the Proxmox storage drives.
* **`setup_proxmox_update_fix.sh`**: Automated installer to apply the update fix across cluster containers.
