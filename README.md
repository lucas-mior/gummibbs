# systemd-boot-btrfs-snapshots
Auto create systemd-boot entries when snapshots are created.
Only arch linux supported.

## Parts
- `build.sh`: installation script
- `snapshot.bash`: create snapshot (meant to be run as cronjob)
- `systemd-boot-btrfsd.bash`: wait for new snapshots and create boot entries
- `systemd-boot-btrfsd.service`: service for the script above
- `systemd-boot-btrfsd.hook`: hook to enable service above

## How it works
The `snapshot.bash` script will create snapshots separated as m̀anual, boot,
hour, day, week and month. Each of those may have multiple snapshots saved as
the current date in format `YYYYMMDD_HHMMSS`.  Btrfs snapshots allow restoring a
subvolume to a previous state.  As `/boot` is on another partition, boot won't
generally work since the kernel/initramfs expected by your restored root file
system is another. So, the `systemd-boot-btrfsd.bash` script also copies the
running kernel and initramfs with the matching name and creates the
corresponding `.conf` boot entry. This implies you must have some spare space
in `/boot`. But don't worry, if another copy already matches the running kernel,
only the entry will be adjusted, no extra copies needed. All this means that you
*will* be able to boot into your system as it was months ago. Of course,
except for other partitions/subvolumes you have used along the way.
Consider adding `nofail` option to non critical partitions/subvolumes in
`/etc/fstab` to avoid surprises.

When run, this script first does some housekeeping:
- Boot entries that point to an inexistent snapshot, kernel or initrd are
  deleted
- Snapshots that have no corresponding boot entry get one. The kernel is
  recovered from the snapshot root and the initramfs is generated
  * Only mkinitcpio and booster supported. If the snapshot contains both booster
    and mkinitcpio installed, then the one in the default boot entry will be
    selected. This could very well introduce a wrong boot entry, if you happened
    to e.g. install booster but not use it, snapshot it, and then start using it
    later.
  * It is possible to get a wrong boot entry if the snapshot is messed up, or if
    you have more than one kernel save in `/lib/modules` (the most recent will
    be selected)

## Installation
```sh
# clone repository
git clone https://github.com/lucas-mior/systemd-boot-btrfs-snapshots
cd systemd-boot-btrfs-snapshots

# install
sudo ./build install
sudo systemctl enable --now systemd-boot-btrfsd.service

# start making snapshots
sudo snapshot.bash manual
```

## Configuration
You may want to set the number of entries kept for each snapshot interval type,
look at `snapshot.bash`. Look at `crontab.example` as a possible way to
configure automatic snapshots.

Make sure that your default boot entry is correctly configured. An example
is given (`entry_example.conf`). The important part is that
`rootflags=subvol=$SUBVOLNAME` is correct.
