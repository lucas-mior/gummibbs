# systemd-boot-btrfs-snapshots
Auto create systemd-boot entries when snapshots are created

## Parts
- `build.sh`: installation script
- `snapshot.bash`: create snapshot (run as cronjob)
- `systemd-boot-btrfsd.bash`: wait for new snapshots and create boot entries
- `systemd-boot-btrfsd.service`: service for the script above
- `systemctl-pacman.hook`: hook to enable service above
