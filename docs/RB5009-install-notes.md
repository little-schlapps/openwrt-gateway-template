# MikroTik RB5009 (UG / UPr): OpenWrt install notes

Supplementary notes to the official guide (OpenWrt wiki, `toh/mikrotik/rb5009ug_s_in`).
Follow the wiki; these are the points that cost time.

## Before you wipe RouterOS

- Export the configuration (`/export show-sensitive file=…`), make a binary
  backup, and save the licence (`/system license output`), then download all
  three. Re-installing RouterOS later needs MikroTik Netinstall.
- RouterOS 7.17+ enforces *device-mode*: `boot-device` cannot be changed until
  `/system device-mode update routerboard=yes` is confirmed by a power cycle
  within the countdown.

## Netbooting U-Boot

- Serve `u-boot.elf` via BOOTP/TFTP on ether1. With dnsmasq, `--bootp-dynamic`
  is required (RouterBOOT sends plain BOOTP), and U-Boot should be handed the
  initramfs instead of `u-boot.elf` again:

  ```
  dnsmasq --no-daemon --port=0 --interface=<if> --bind-dynamic \
    --dhcp-range=192.168.1.100,192.168.1.150,12h --bootp-dynamic \
    --dhcp-vendorclass=set:uboot,U-Boot \
    --dhcp-boot=tag:uboot,openwrt-mvebu-cortexa72-mikrotik_rb5009-initramfs-uImage.itb \
    '--dhcp-boot=tag:!uboot,u-boot.elf' \
    --enable-tftp --tftp-root=<dir> --log-dhcp
  ```

  (Quote the `!uboot` argument; bash history expansion breaks it otherwise.)

- **If RouterBOOT downloads `u-boot.elf` and then silently boots RouterOS**
  (no further DHCP/TFTP from the board, ~60 s later RouterOS's DHCP client
  appears): newer primary RouterBOOT versions may refuse to start it. Using the
  **backup (factory) booter** fixed this:

  ```
  /system routerboard settings set force-backup-booter=yes boot-device=try-ethernet-once-then-nand boot-protocol=bootp
  ```

  Leave `force-backup-booter=yes` set after the install: RouterBOOT later
  starts U-Boot from NAND, and the primary booter may refuse it there as well.

- `try-ethernet-once` is single-shot: if an attempt fails (no server ready,
  wrong port), set it again before the next power cycle.
- With a USB stick (FAT32, first partition) holding the initramfs `.itb`,
  U-Boot boots it from USB before trying the network.

## After the initramfs boots

Copy `u-boot.elf` and the sysupgrade image to `/tmp`, verify checksums, then
as in the wiki: `yafut` U-Boot into the YAFFS `kernel` file, `ubiformat` the
`ubi` MTD, `sysupgrade -n`. Read the YAFFS file back and compare checksums
before formatting.

## Known limitation: PoE-out on RB5009UPr

As of OpenWrt 25.12 there is no supported PoE-out control for the UPr model.
The PoE controller keeps the state RouterOS last configured, so a PoE device
may stay powered, but it cannot be switched or monitored. Use an injector if
you need deterministic power.
