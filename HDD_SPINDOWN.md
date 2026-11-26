# Proxmox HDD Spindown & TDAS Enclosure Sleep Configuration

This document records the modifications made to the Proxmox VE host (`192.168.50.164`) to configure HDD spindown and enable the TerraMaster TDAS enclosure to enter low-power sleep mode (which shuts off the internal enclosure fan) when inactive.

---

## 1. System Topology & Targets
* **Host OS & Containers NVMe SSD (`nvme0n1`):** Runs Proxmox VE system partitions (`/`, `swap`) and `local-lvm` thin pool for LXC container root filesystems. Stays active 24/7.
* **Storage HDDs (TerraMaster TDAS Enclosure, USB ID `174c:235c`):**
  * `/dev/sda` (4TB BTRFS) — `ata-ST4000LM024-2AN17V_WFG13F5D` (Mounted on host `/mnt/smalldrv`; cold read-only media archive, `3.0G` free)
  * `/dev/sdb` (12.7TB exFAT) — `ata-ST14000NM0121_ZKL2Q7S5` (Mounted on host `/mnt/exfat_bigdrv_host`)
  * `/dev/sdc` (21.8TB BTRFS) — `ata-ST24000DM001-3Y7103_ZXA127GW` (Mounted on host `/mnt/bigrust`)

---

## 2. Configured Changes

### A. Stopping Proxmox Background Wake-ups
To prevent Proxmox from waking the HDDs every few seconds:
1. **Disabled Static PVE Directory Polling:**
   Removed `small-drv` from `/etc/pve/storage.cfg` and kept `big-rust` disabled between backups. `/etc/vzdump.conf` invokes `/usr/local/bin/vzdump-hook.sh` to temporarily enable `big-rust` on `job-start`/`job-init` and disable it again on `job-end`/`job-abort`, preventing `pvestatd` from polling `sdc` between backups. (LXCs access these directories directly via host bind-mounts).
2. **LVM Exclusions (`/etc/lvm/lvm.conf`):**
   Updated `global_filter` to reject scans on your three HDD IDs, preventing LVM daemon wake-ups:
   ```text
   global_filter=["r|/dev/zd.*|","r|/dev/rbd.*|","r|/dev/disk/by-id/ata-ST4000LM024-2AN17V_WFG13F5D.*|","r|/dev/disk/by-id/ata-ST14000NM0121_ZKL2Q7S5.*|","r|/dev/disk/by-id/ata-ST24000DM001-3Y7103_ZXA127GW.*|"]
   ```
3. **SMART Scanning Exclusions (`/etc/smartd.conf`):**
   Appended `,q` to `-n standby` (`-n standby,q`) in the `DEVICESCAN` directive, instructing the SMART daemon to skip checking drives that are in standby and suppressing log spam.

---

### B. Disk Spindown Management (`hd-idle`)
Debian's `/usr/lib/udev/hdparm` -> `95hdparm-apm` (`hdparm_try_apm`) silently skips USB-connected disks (`ID_PATH` matching `pci-*-usb-*`) and disks without ATA APM support (`sdb`/`sdc`). Spindown is instead managed by `hd-idle.service` (`adelolmo/hd-idle` 1.21+) using SAT ATA pass-through (`-c ata`), which sends `ATA STANDBY IMMEDIATE` (`0xe0`) directly through the `174c:235c` ASMedia bridges.

* **Configuration (`/etc/default/hd-idle`):**
  Configured a **45-minute** (`2700s`) idle timeout specifically for the three HDD serial IDs (`-i 0` disables spindown for the NVMe OS disk; `-s 1` resolves symlinks dynamically):
  ```text
  START_HD_IDLE=true
  HD_IDLE_OPTS="-i 0 -c ata -s 1 -a /dev/disk/by-id/ata-ST4000LM024-2AN17V_WFG13F5D -i 2700 -a /dev/disk/by-id/ata-ST14000NM0121_ZKL2Q7S5 -i 2700 -a /dev/disk/by-id/ata-ST24000DM001-3Y7103_ZXA127GW -i 2700"
  ```
* **SMART Polling Coordination (`/etc/default/smartmontools`):**
  Configured `smartd_opts="-q never -i 21600"` (6-hour interval) alongside `-n standby,q` in `/etc/smartd.conf` so `smartd` checks do not wake USB-suspended bridges every 30 minutes and skip drives in `STANDBY`.
* **Legacy `/etc/hdparm.conf`:** Device spindown blocks were removed to avoid confusion.

---

### C. Enclosure Sleep & Fan Shut-Off (UAS Quirk + Auto-Suspend)
Connecting DAS enclosures via USB to Linux hosts introduces link power-management issues. When the USB connection tries to sleep, UAS (USB Attached SCSI) protocol bugs inside the ASMedia chip of the TDAS trigger USB connection resets and device letter renames.

To enable the enclosure fan to turn off safely during idle times:
1. **Disabled UAS (UAS Quirk):**
   Created `/etc/modprobe.d/tdas-quirks.conf` to force the device to use the older, extremely stable `usb-storage` driver instead of `uas`. This enables stable ATA standby translation:
   ```text
   options usb-storage quirks=174c:235c:u
   ```
2. **Re-enabled USB Auto-Suspend with a 60-Minute Timeout (Strictly > `hd-idle`):**
   Configured `/etc/udev/rules.d/50-tdas-spindown.rules` to auto-suspend the USB link and SCSI block devices **60 minutes (3600s)** after inactivity, ensuring platters are already cleanly in `STANDBY` (at 45 min) before the USB bridge suspends:
   ```text
   # Enable USB auto-suspend for the TerraMaster TDAS USB enclosure device (60-minute timeout, strictly > 45m hd-idle)
   ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="174c", ATTR{idProduct}=="235c", ATTR{power/control}="auto", ATTR{power/autosuspend}="3600"

   # Enable block-level SCSI device auto-suspend for the disks inside the TDAS enclosure (60-minute timeout)
   ACTION=="add|change", SUBSYSTEM=="scsi", DRIVERS=="sd", ATTRS{vendor}=="TerraMas", ATTR{power/control}="auto", ATTR{power/autosuspend_delay_ms}="3600000"
   ```
3. **Media Stack & Batch Schedule Alignment:**
   - **Sonarr & Radarr (LXC 102):** `rescanAfterRefresh` set to `afterManual` (avoids 12h/24h full-directory tree walks across `sdb` and `sdc`).
   - **Plex (LXC 100):** `FSEventLibraryUpdatesEnabled=1` (`inotify`), `ScheduledLibraryUpdatesEnabled=0` (no timed folder polling).
   - **Sunday Maintenance Window (`/etc/cron.d/security_clips_cleanup`):** Moved from `02:30` to `03:35` so host clip pruning aligns right after HA's `03:15` weekly archival and before `04:00` `vzdump`.
4. **Rebuilt Boot Image:**
   Rebuilt the host boot ramdisk using `update-initramfs -u` to apply the quirks at boot.

---

### D. Filesystem Integrity (`fsck.exfat` & Monthly `btrfs scrub`)
1. **Boot-Time `exFAT` Check (`/etc/fstab`):**
   Set `<pass> = 2` on `/mnt/exfat_bigdrv_host` (`UUID=005B-2D8A`) so `systemd-fsck` runs `fsck.exfat -a` at boot before mounting or starting LXCs. (`exFAT` cannot be checked online while mounted.)
2. **Monthly Online `Btrfs` Scrub (`/etc/systemd/system/btrfs-scrub-das.{service,timer}`):**
   Created a monthly systemd timer (`OnCalendar=*-*-01 11:00:00`, daytime to avoid nighttime noise) that sequentially runs:
   ```bash
   /usr/bin/btrfs scrub start -B /mnt/bigrust && /usr/bin/btrfs scrub start -B /mnt/smalldrv
   ```
   (`btrfs` uses `pass = 0` in `/etc/fstab` because `btrfs scrub` verifies data/metadata checksums online while mounted; scrubbing `sda` monthly also verifies the 3.7 TB cold read-only archive without weekly wakeups.)

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
If you make changes to `/etc/default/hd-idle` or `/etc/default/smartmontools`, apply them without rebooting:
```bash
systemctl restart hd-idle
systemctl restart smartmontools
```
For changes to `/etc/udev/rules.d/50-tdas-spindown.rules`:
```bash
udevadm control --reload-rules && udevadm trigger --subsystem-match=usb --subsystem-match=scsi
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

### Offline `exFAT` Check & Manual `Btrfs` Scrub
`fsck.exfat` requires `/mnt/exfat_bigdrv_host` to be unmounted (stop bind-mounted LXCs first):
```bash
for id in 100 101 102 106; do pct shutdown $id --timeout 45; done
umount /mnt/exfat_bigdrv_host && fsck.exfat -p /dev/sdb2 && mount /mnt/exfat_bigdrv_host
for id in 100 101 102 106; do pct start $id; done
```
Check Btrfs error counters or run an on-demand scrub without stopping services:
```bash
btrfs device stats /mnt/bigrust /mnt/smalldrv
systemctl start btrfs-scrub-das.service
```
