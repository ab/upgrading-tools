# File:
#       /etc/initramfs-tools/hooks/loadinitramfskey.sh
#
# Description:
#       Called by update-initramfs and loads getinitramfskey.sh to obtain the system decryption key.
#
# Purpose:
#       Used with getinitramfskey.sh in full disk encryption to decrypt the system LUKS partition,
#       to prevent being asked twice for the same passphrase.

PREREQ=""

prereqs()
{
    echo "${PREREQ}"
}

case "${1}" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. "${CONFDIR}"/initramfs.conf

. /usr/share/initramfs-tools/hook-functions

if [ ! -f "${DESTDIR}"/lib/cryptsetup/scripts/getinitramfskey.sh ]
then
    if [ ! -d "${DESTDIR}"/lib/cryptsetup/scripts/ ]
    then
        mkdir --parents "${DESTDIR}"/lib/cryptsetup/scripts/
    fi
    cp /lib/cryptsetup/scripts/getinitramfskey.sh "${DESTDIR}"/lib/cryptsetup/scripts/
fi

if [ ! -d "${DESTDIR}"/keys/ ]
then
    mkdir -p "${DESTDIR}"/keys/
fi

cp /keys/cryptodisk.key "${DESTDIR}"/keys/

