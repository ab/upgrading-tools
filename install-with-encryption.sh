#!/bin/bash
set -euo pipefail

# See https://help.ubuntu.com/community/ManualFullSystemEncryption
# and https://www.chinnodog.com/ubuntu/ubuntu-fde-boot/

#Ubuntu 18.04, 19.04
#Full disk encryption

usage() {
  cat >&2 <<EOM
usage: $(basename "$0") FDE_DEV EFI_DEV ROOT_PARTITION_SIZE

FDE_DEV: physical partition for disk encryption, e.g. "/dev/nvme0n1p6"
EFI_DEV: physical partition where EFI is already, e.g. "/dev/nvme0n1p2"
ROOT_PARTITION_SIZE: size of LVM root partition, e.g. "20G"
EOM
}

run() {
  echo >&2 "+ $*"
  "$@"
}

set_fde_uuid_vars() {
  # get UUID of FDE partition for cryptsetup
  fde_uuid="$(run blkid "$fde_dev" | grep -wo 'UUID=\S*' | tr -d '"' | cut -f2 -d=)"
  unlocked_luks_basename="luks-$fde_uuid"
}

pre_install_steps() {
  echo "Using $efi_dev as /boot/efi:"
  res="$(run blkid "$efi_dev")"
  echo "$res"
  if ! [[ $res == *"EFI system partition"* ]]; then
    echo "WARNING: $efi_dev does not have label 'EFI system partition'"
    read -r -p "Press enter to continue regardless!"
  fi

  echo
  echo "DANGER DANGER DANGER DANGER DANGER DANGER DANGER"
  echo "I am about to format $fde_dev as a physical volume for encryption."
  echo "Existing data on this partition will be lost!"
  echo "Current contents:"
  run lsblk "$fde_dev"
  run file -s "$fde_dev"

  read -p "Press enter to DESTROY AND REFORMAT $fde_dev!!!!! "

  run cryptsetup luksFormat "$fde_dev"

  set_fde_uuid_vars

  run cryptsetup open "$fde_dev" "$unlocked_luks_basename"
  open_dev="/dev/mapper/$unlocked_luks_basename"

  vg_name='main'

  run pvcreate "$open_dev"
  run vgcreate "$vg_name" "$open_dev"

  run lvcreate -n root -L "$root_partition_size" "$vg_name"
  run lvcreate -n home -l 100%FREE "$vg_name"

  cat <<EOM

Now that we have created the LVM partitions, please run the standard
Ubuntu installer.

DO NOT REBOOT at the end of the process. Click "Continue testing" and return to
this window instead. This script will take steps to ensure that your new
installation is bootable.

EOM
  read -r -p "Run the installer now. Once it's done, press enter to continue... "
}

post_install_steps() {

  set_fde_uuid_vars

  echo "Mounting target install partitions"

  # chroot into the target

  if ! grep /target /proc/mounts; then
    run mount /dev/main/root /target
  fi

  # create mountpoint for EFI partition
  if [ ! -d /target/boot/efi ]; then
    mkdir -v /target/boot/efi
    run touch /target/boot/efi/NOT-MOUNTED
    chmod -v 444 /target/boot/efi/NOT-MOUNTED
    chmod -v 555 /target/boot/efi
  fi

  run mount $efi_dev /target/boot/efi

  for fs in proc sys dev dev/pts run; do
    run mount --bind /$fs /target/$fs
  done

  echo "Fixing target grub boot configuration"

  if ! grep 'GRUB_ENABLE_CRYPTODISK="y"' /target/etc/default/grub; then
    tee -a /target/etc/default/grub <<EOM

# enable luks disk encryption support
GRUB_ENABLE_CRYPTODISK="y"
EOM
  fi

  # Do not hide grub menu, if previously configured
  run sed --in-place --expression='/GRUB_TIMEOUT_STYLE=hidden/ s/hidden/menu/' /target/etc/default/grub

  # TODO: not necessary?
  #   GRUB_CMDLINE_LINUX="cryptodevice=<PARTITION_UUID>:<UNLOCKED_LUKS_DEV>

  echo "Installing initramfs hooks"

  # Install initramfs hook and script.
  run cp -v "$(dirname "$0")/lib/loadinitramfskey.sh" /target/etc/initramfs-tools/hooks/loadinitramfskey.sh
  run cp -v "$(dirname "$0")/lib/getinitramfskey.sh" /target/lib/cryptsetup/scripts/getinitramfskey.sh

  run tee /target/etc/initramfs-tools/conf.d/luks-umask.conf <<EOM
# Make sure encryption key is not world readable in initramfs
UMASK=0077
EOM

  echo "Generating keyfile"

  # create a keyfile to unlock the main disk, which avoids double prompting in grub and in initramfs
  mkdir -vp /target/keys
  keyfile=/target/keys/cryptodisk.key
  # NB: keyfile location is hardcoded in loadinitramfskey.sh hook as /keys/cryptodisk.key
  if [ -e "$keyfile" ]; then
    echo "Keyfile $keyfile already exists!"
    ls -l "$keyfile"
    read -r -p "Press enter to continue with existing keyfile anyway!"
  else
    run touch "$keyfile"
    run chmod 000 "$keyfile"
    run head -c 64 /dev/urandom > "$keyfile"
  fi
  run cryptsetup luksAddKey "$fde_dev" "$keyfile"
  echo "Added key to luks volume"

  # We could use /bin/cat as keyscript, but this one is a wrapper that will
  # prompt for the password manually if the keyfile is missing, which makes it
  # somewhat more foolproof.
  run tee /target/etc/crypttab <<EOM
$unlocked_luks_basename UUID=$fde_uuid /keys/cryptodisk.key luks,discard,noearly,keyscript=/lib/cryptsetup/scripts/getinitramfskey.sh
EOM

  # TODO: do we need to add the UUID to /etc/default/grub GRUB_CMDLINE_LINUX="cryptodevice=<uuid>:<unlocked_luks_basename>" ?

  run chroot /target update-grub
  run chroot /target update-initramfs -u -k all

}

# ============================================================

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  set -x
  exec sudo "$0" "$@"
fi

fde_dev="$1"
efi_dev="$2"
root_partition_size="$3"

if [ -n "${SKIP_PRE_INSTALL-}" ]; then
  echo "Skipping pre_install_steps"
else
  pre_install_steps
fi

post_install_steps
