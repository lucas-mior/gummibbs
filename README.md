# gummibbs
**g**ummi **b**oot **b**trfs **s**napshots. As systemd-boot was gummiboot.

Auto create systemd-boot entries when snapshots are created.
Only arch linux supported.

## Parts
- `build.sh`: installation script
- `snapshot.bash`: create snapshot (meant to be run as cronjob)
- `gummibbs.bash`: wait for new snapshots and create boot entries
- `gummibbs.service`: service for the script above
- `gummibbs.hook`: hook to enable service above

## How it works
The `snapshot.bash` script will create snapshots separated as manual, boot,
hour, day, week and month. Each of those may have multiple snapshots saved as
the current date in format `YYYYMMDD_HHMMSS`.  Btrfs snapshots allow restoring a
subvolume to a previous state.  As `/boot` is on another partition, boot won't
generally work since the kernel/initramfs expected by your restored root file
system is another. So, the `gummibbs.bash` script also copies the
running kernel and initramfs with the matching name and creates the
corresponding `.conf` boot entry. This implies you must have some spare space in
`/boot`. But don't worry, if another copy already matches the running kernel,
only the entry will be adjusted, no extra copies needed. All this means that you
*will* be able to boot into your system as it was months ago (but see
[gotchas](#Gotchas)).

When run, this script first does some housekeeping:
- Boot entries that point to an nonexistent snapshot, kernel or initrd are
  deleted
- Snapshots that have no corresponding boot entry get one. The kernel is
  recovered from the snapshot root and the initramfs is generated
  * If the snapshot contains more than one initramfs generator installed, then
    the one in the default boot entry will be selected. This could very well
    introduce a wrong boot entry, if you happened to e.g.  install booster but
    not use it, snapshot it, and then start using it later.
  * It is possible to get a wrong boot entry if the snapshot is messed up, or if
    you have more than one kernel saved in `/lib/modules` (the most recent will
    be selected)

## Gotchas
While it is possible to restore the old kernel and regenerate the initramfs,
old root file systems might fail for other reasons:
- Partitions or btrfs subvolumes expected by `/etc/fstab` no longer exist
  * consider adding `nofail` option
  * consider using
    file system LABEL,
    partition PARTLABEL,
    or mapped device path (`/dev/mapper/name`),
    but avoid UUIDs or (god forbid) generic block device path (e.g `/dev/sda1`)

## Installation
### AUR
```sh
yay -S gummibbs
```

### Manual
```sh
# clone repository
git clone https://github.com/lucas-mior/gummibbs
cd gummibbs

# install
sudo ./build.sh install
sudo systemctl enable --now gummibbs.service

# start making snapshots
sudo snapshot.bash manual
```

### Existing snapshots
This tool uses the directory `/.snapshots/$kind` to store the snapshots.  If you
have old snapshots that you would like to be put in the same directory, you can
do so, but beware that the `snapshot.bash` script **deletes** old snapshots
based on how many you want to keep (`/etc/gummibbs.conf`). Also
beware of the naming convention. The snapshot must be named
`YYYYMMDD_HHMMSS` or things will break.

## Prerequisites
- `/boot` must be `vfat` partition
- Root filesystem must be a btrfs subvolume with a valid name:
  * subvolume name must not match `grep -E ([|/&\\$\(\)*+[]|])`.
  * suggestion: Use `@`.
- Initramfs filename must match the name of the generator used:
  * `$GENERATOR-$KERNEL_TYPE.img` must match the initramfs generator and kernel
  * Note that by default, only booster creates the initramfs with its name. You
    will have to change the config for mkinitcpio or dracut in order to generate
    proper names for the initramfs.
- Systemd-boot properly configured
  * Make sure that your default boot entry is correctly configured. An example
    is given (`entry_example.conf`).
    Specific for this script to work correctly are the options:
    + `rootflags=subvol=$SUBVOLNAME`
    + `initrd $GENERATOR-$KERNEL_TYPE.img`
- Unified kernel images are not supported and will cause the script to exit,
  if detected

### mkinitcpio
Example without fallback image. Note that the `default_image` line is changed to
keep track of the generator used.
```sh
$ cat /etc/mkinitcpio.d/linux.preset
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/mkinitcpio-linux.img"
```

### dracut
When creating the initramfs, use one of the following commands depending on
which kernel you are using:
```sh
dracut /boot/dracut-linux.img
dracut /boot/dracut-linux-lts.img
```

## Configuration
The amount of snapshots kept for each type is configured through
`/etc/gummibbs.conf`
For automatic snapshots, look at Look at `crontab.example`.
