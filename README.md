# System upgrading tools

The Ubuntu Linux installation and upgrading tools don't always offer all of the
functionality needed for more complicated full disk encryption setups.

This repository contains an assortment of scripts that have been useful to me
personally during OS installation / upgrade processes.

See especially `bootstrap-gpg-ssh`, which makes it easy on a brand new machine
to use an SSH key from a hardware token like a Yubikey.

## LUKS1 / LUKS2 and future work

At the time these scripts were first created, grub did not support the LUKS2
container format. As a result, the scripts were modified to ensure the use of
LUKS1 containers when setting up the encrypted disks.

But since that time, grub has added support for LUKS2. But it may take some
time for the newer version / luks module to propage through distributions.

In addition, through trial and error it seems that on my test hardware, grub is
*vastly* slower at processing PBKDF2 iterations compared to the linux kernel's
implementation of LUKS. This means that if a LUKS1 partition is set up using a
timed key stretching phase of 1 second for a given passphrase, that grub could
take as much as 30-60 seconds to derive the same resulting key.

This is fairly intolerable, so it's necessary to significantly reduce the
PBKDF2 iterations in order to get a reasonable boot decryption time.

### TPM / bitlocker

Ideally, we would instead take a bitlocker style approach to encryption, where
the disk encryption key by default is unlocked without a passphrase prompt by
unsealing a key using the TPM. This allows us to have a trusted boot
environment and to unlock the disk without any prompt. (This does imply a
passphrase on grub or otherwise disabling recovery mode.)

There are a number of articles on how to do this, which I'm hoping to test run
in the future.

Most of the guides start with resetting the TPM / taking ownership over it,
which would wipe any existing bitlocker / TPM usage.

## Random notes

Displaying EFI boot order / loaders:
```sh
efibootmgr -v
```

Displaying currently enrolled MOK signing keys for SecureBoot:
```sh
mokutil --list-enrolled
```

One of these should match the module key in `/var/lib/shim-signed/mok/`.
