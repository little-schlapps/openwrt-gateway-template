# openwrt-gateway-template

Opinionated, scripted setup for an **OpenWrt 25.12 home / small-office gateway**
with two uplinks, an isolated IoT / camera segment, network-wide DNS filtering
and lightweight security monitoring. Every step is a small, readable POSIX
shell script driven by one settings file.

```
                 wan1 (primary) ──┐            ┌── LAN bridge (br-lan, STP)
                                  │  OpenWrt   │     clients, access points
                 wan2 (backup) ───┤  gateway   │
                                  │            └── IoT port ── IoT AP / cameras
                                  └─ mwan3 failover            (own subnet + zone,
                                                               egress via wan2 only)
```

## What you get

| Area | Behaviour |
|---|---|
| **Dual WAN** | `wan1` primary, `wan2` backup via **mwan3** with ping health checks (detects "link up but no internet"); failover ≈ 15 s, failback ≈ 15 s |
| **IoT segment** | Dedicated port and subnet, own firewall zone: internet yes, IoT→LAN no, LAN→IoT yes; router reachable only for DHCP/DNS |
| **IoT egress pinning** | Policy routing sends IoT traffic **only** via `wan2`; a firewall rule rejects it on `wan1` (no silent fallback) |
| **DNS** | **AdGuard Home** on :53 (DoH upstreams, blocklists, per-client rules); dnsmasq kept on :54 for DHCP and `.lan` names; query log in RAM |
| **Monitoring** | nlbwmon (traffic per host), addrwatch (new IP/MAC pairs to syslog) |
| **Security** | CrowdSec + nftables bouncer (community blocklist on the WAN devices), Snort 3 IDS on the IoT segment (afpacket, alerts to JSON + syslog) |
| **QoS** | SQM/cake prepared on the backup WAN, disabled until needed |
| **IPv6** | Disabled at configuration level (optional step) |
| **LuCI** | "Layer 3 Interfaces" section on Status → Overview (zone, ports, addressing per interface); optional [luci-app-snort](https://github.com/little-schlapps/luci-app-snort) and Argon theme from checksum-verified release files |
| **Tools** | `healthcheck.sh` (read-only status of everything), `failover-drill.sh` (simulated primary-WAN outage with timings) |

## Requirements

- OpenWrt **25.12** (apk package manager) with LuCI
- Two WAN-capable ports + one spare port for the IoT segment
- ~200 MB free flash, ≥ 512 MB RAM recommended (Snort + CrowdSec + AdGuard ≈ 300 MB)
- Tested on a MikroTik RB5009 (mvebu/cortexa72). See [docs/RB5009-install-notes.md](docs/RB5009-install-notes.md).

## Usage

Copy the repository to the router (e.g. `/root/gateway-template`), then:

```sh
cd /root/gateway-template
cp config.env.example config.env
vi config.env                      # ports, subnets, interface names

DRY_RUN=1 sh scripts/10-network-base.sh   # every step supports a dry run
```

Run the steps in order, applying and checking each one before the next:

| Step | Script | Then apply with |
|---|---|---|
| 0 | `scripts/00-packages.sh` | — |
| 1 | `scripts/10-network-base.sh` | `service network reload; service firewall reload; service dropbear restart` |
| 2 | `scripts/20-iot-segment.sh` | `service network reload; service firewall reload; service dnsmasq restart` |
| 3 | `scripts/30-mwan3.sh` | `service mwan3 restart` |
| 4 | `scripts/40-adguardhome.sh` | (applies itself, rolls back on DNS failure) |
| 5 | `scripts/50-security.sh` | (restarts its services) |
| 6 | `scripts/60-ipv6-off.sh` *(optional)* | `service network reload; service dnsmasq restart` |
| 7 | `scripts/70-luci-extras.sh` | log out of LuCI and back in |

Afterwards: `sh tools/healthcheck.sh`, and once in a quiet moment `sh tools/failover-drill.sh`.

**Before you start**

- Keep a console/serial or out-of-band path to the router. Network reloads
  briefly interrupt the LAN (longer with STP: 2 × `forward_delay`).
- Every script backs up the files it changes to `/root/cfg-backup/<timestamp>-<step>/`.
- The scripts are written for a **fresh** OpenWrt install and use named UCI
  sections, so re-running them is safe. On a router you configured by hand,
  similar zones/rules with other names would end up duplicated: run with
  `DRY_RUN=1` first and compare.
- Secrets are never stored in this repository or in `config.env`; the AdGuard
  admin password is asked for at run time (or taken from `AGH_PASSWORD`).

## Design notes and gotchas

See [docs/LESSONS.md](docs/LESSONS.md): the non-obvious problems this template
works around (DHCP client-id, fw4 zone devices, pcap alert delay, mesh nodes and
bridge loops, IoT routing vs. mwan3, and more).

## License

Apache-2.0. No warranty: review the scripts and test on your own hardware.
