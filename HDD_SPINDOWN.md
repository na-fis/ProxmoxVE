# Proxmox HDD Spindown & TDAS Enclosure Sleep Configuration

This document records the modifications made to the Proxmox VE host (`192.168.50.164`) to configure HDD spindown and enable the TerraMaster TDAS enclosure to enter low-power sleep mode (which shuts off the internal enclosure fan) when inactive.

---

## 1. System Topology & Targets
* **Host OS & Containers NVMe SSD (`nvme0n1`):** Runs Proxmox VE system partitions (`/`, `swap`) and `local-lvm` thin pool for LXC container root filesystems. Stays active 24/7.
* **Storage HDDs (TerraMaster TDAS Enclosure, USB ID `174c:235c`):**
  * `/dev/sda` (4TB BTRFS) — `ata-ST4000LM024-2AN17V_WFG13F5D` (Mounted on host `/mnt/smalldrv`)
  * `/dev/sdb` (12.7TB exFAT) — `ata-ST14000NM0121_ZKL2Q7S5` (Mounted on host `/mnt/exfat_bigdrv_host`)
  * `/dev/sdc` (21.8TB BTRFS) — `ata-ST24000DM001-3Y7103_ZXA127GW` (Mounted on host `/mnt/bigrust`)

---

## 2. Configured Changes

### A. Stopping Proxmox Background Wake-ups
To prevent Proxmox from waking the HDDs every few seconds:
1. **Removed PVE Directory Storages:**
   Removed `small-drv` and `big-rust` directories from `/etc/pve/storage.cfg` using `pvesm remove`. (LXCs continue to access these directories directly via host bind-mounts).
2. **LVM Exclusions (`/etc/lvm/lvm.conf`):**
   Updated `global_filter` to reject scans on your three HDD IDs, preventing LVM daemon wake-ups:
   ```text
   global_filter=["r|/dev/zd.*|","r|/dev/rbd.*|","r|/dev/disk/by-id/ata-ST4000LM024-2AN17V_WFG13F5D.*|","r|/dev/disk/by-id/ata-ST14000NM0121_ZKL2Q7S5.*|","r|/dev/disk/by-id/ata-ST24000DM001-3Y7103_ZXA127GW.*|"]
   ```
3. **SMART Scanning Exclusions (`/etc/smartd.conf`):**
   Appended `,q` to `-n standby` (`-n standby,q`) in the `DEVICESCAN` directive, instructing the SMART daemon to skip checking drives that are in standby and suppressing log spam.

---

### B. Disk Spindown Management (`hdparm`)
Spindown is managed natively by Debian's built-in `hdparm` utility. 
* **Configuration (`/etc/hdparm.conf`):**
  Configured a **30-minute** timeout (`spindown_time = 240`) specifically for the three HDD serial IDs:
  ```text
  /dev/disk/by-id/ata-ST4000LM024-2AN17V_WFG13F5D {
      spindown_time = 240
  }
  /dev/disk/by-id/ata-ST14000NM0121_ZKL2Q7S5 {
      spindown_time = 240
  }
  /dev/disk/by-id/ata-ST24000DM001-3Y7103_ZXA127GW {
      spindown_time = 240
  }
  ```
* **Execution:** Handled automatically at boot via the system udev rule `/lib/udev/rules.d/85-hdparm.rules` when block devices are added. (Note: the legacy `hd-idle` daemon was disabled and stopped to prevent conflicts).

---

### C. Enclosure Sleep & Fan Shut-Off (UAS Quirk + Auto-Suspend)
Connecting DAS enclosures via USB to Linux hosts introduces link power-management issues. When the USB connection tries to sleep, UAS (USB Attached SCSI) protocol bugs inside the ASMedia chip of the TDAS trigger USB connection resets and device letter renames.

To enable the enclosure fan to turn off safely during idle times:
1. **Disabled UAS (UAS Quirk):**
   Created `/etc/modprobe.d/tdas-quirks.conf` to force the device to use the older, extremely stable `usb-storage` driver instead of `uas`. This enables stable ATA standby translation:
   ```text
   options usb-storage quirks=174c:235c:u
   ```
2. **Re-enabled USB Auto-Suspend with a 30-Minute Timeout:**
   Created `/etc/udev/rules.d/50-tdas-spindown.rules` to tell the kernel to auto-suspend the USB link and SCSI block devices 30 minutes (1800s) after they go quiet:
   ```text
   # Enable USB auto-suspend for the TerraMaster TDAS USB enclosure device (30-minute timeout)
   ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="174c", ATTR{idProduct}=="235c", ATTR{power/control}="auto", ATTR{power/autosuspend}="1800"

   # Enable block-level SCSI device auto-suspend for the disks inside the TDAS enclosure (30-minute timeout)
   ACTION=="add|change", SUBSYSTEM=="scsi", DRIVERS=="sd", ATTRS{vendor}=="TerraMas", ATTR{power/control}="auto", ATTR{power/autosuspend_delay_ms}="1800000"
   ```
3. **Rebuilt Boot Image:**
   Rebuilt the host boot ramdisk using `update-initramfs -u` to apply the quirks at boot.

---

## 3. Maintenance & Verification Commands

### Checking Disk Power State (Without Waking Them)
Use `smartctl` with the `-d sat` parameter to query power state safely without waking the drives:
```bash
smartctl -i -n standby -d sat /dev/sda
```
* **If sleeping:** Returns `Device is in STANDBY mode, exit(2)`.
* **If active:** Returns standard disk info and `Power mode is: ACTIVE or IDLE`.

### Applying Configuration Changes Manually
If you make changes to `/etc/hdparm.conf` and want to apply them without rebooting:
```bash
udevadm trigger --subsystem-match=block
```

### Remounting Drives (If ever manually disconnected)
If you physically disconnect the DAS or reset it:
```bash
mount -a
pct reboot 100 # Plex
pct reboot 101 # SABnzbd
pct reboot 102 # Arr-stack
pct reboot 106 # Nextcloud
```
