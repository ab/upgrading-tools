# File:
#       /lib/cryptsetup/scripts/getinitramfskey.sh
#
# Description:
#       Called by initramfs using busybox ash to obtain the decryption key for the system.
#
# Purpose:
#       Used with loadinitramfskey.sh in full disk encryption to decrypt the system LUKS partition,
#       to prevent being asked twice for the same passphrase.

KEY="${1}"

if [ -f "${KEY}" ]
then
    cat "${KEY}"
else
    PASS=/bin/plymouth ask-for-password --prompt="Key not found. Enter LUKS Password: "
    echo "${PASS}"
fi
