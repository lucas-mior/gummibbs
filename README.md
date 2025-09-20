# systemd-boot-btrfs-snapshots
Auto create systemd-boot entries when snapshots are created

## Parts
- `build.sh`: installation script
- `snapshot.bash`: create snapshot (meant to be run as cronjob)
- `systemd-boot-btrfsd.bash`: wait for new snapshots and create boot entries
- `systemd-boot-btrfsd.service`: service for the script above
- `systemctl-pacman.hook`: hook to enable service above

## How it works
The `snapshot.bash` script will create snapshots separated as m̀anual, boot,
hour, day, week and month. Each of those may have multiple snapshots saved as
the current date in format `YYYYMMDD_HHMMSS`.  Btrfs snapshots allow restoring a
subvolume to a previous state.  As `/boot` is on another partition, boot won't
generally work since the kernel/initramfs expected by your restored root file
system is another. So, the `systemd-boot-btrfsd.bash` script also copies the
running kernel and initramfs with the matching name and creates the
corresponding `.conf` boot entry.

## Installation
```sh
git clone https://github.com/lucas-mior/systemd-boot-btrfs-snapshots
cd systemd-boot-btrfs-snapshots

sudo ./build install
sudo systemctl enable --now systemd-boot-btrfsd.service
```

## Configuration
You may want to set the number of entries kept for each snapshot interval type,
look at `snapshot.bash`.
