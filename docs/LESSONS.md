# Lessons learned

Problems hit while building this setup, and how the template handles them.

## WAN / routing

**DHCP server ignores requests with a client-id.** Some ISP DHCP servers
OFFER an address but never ACK the REQUEST when the client sends option 61
(client-id), which OpenWrt's udhcpc does by default. The lease previously
issued to the same MAC (e.g. by the vendor firmware) is only honoured without
it. Symptom: endless `broadcasting select for …` in the log. Fix:
`uci set network.<wan>.sendclientid='none'` (`WANx_SENDCLIENTID` in `config.env`).

**Uplink without NAT after boot.** fw4 resolves a zone's `network` list to
devices at load time; an interface without an address at that moment (e.g. a
slow DHCP WAN) is left out of `wan_devices`, so traffic leaving through it is
neither masqueraded nor accepted. Router-originated traffic still works, which
makes it confusing. Fix: list the devices explicitly with `option device` in
the zone (done in `10-network-base.sh`).

**Two DHCP WANs with the same gateway.** Carrier-grade NAT providers often
hand out the same gateway address on both links. With equal metrics only the
first default route is installed (the kernel rejects the duplicate) and
netifd does not retry. Give each WAN its own metric.

**Metrics alone are not failover.** A metric only switches when the link goes
down; mwan3's health checks also catch "link up, no internet". Existing
connections stay on the path they started on, so a continuous ping may show no
loss in a simulated outage; a real outage drops them once.

**Policy routing next to mwan3.** The IoT rules use priorities 90/100, below
mwan3's 1001+, so IoT traffic never reaches mwan3:
`90: lookup main suppress_prefixlength 0` keeps local/LAN routes working,
`100: from <IoT net> lookup <table>` sends everything else to the egress WAN.
The egress gateway is learned from DHCP by a hotplug script, and a firewall
rule rejects IoT traffic on the other WAN so there is no fallback.

**Leaked upstream DHCP server.** If a WAN port is accidentally left in the LAN
bridge, the upstream router's DHCP server answers LAN clients too: clients
"sometimes" get addresses, access points get upstream addresses. Check
`br-lan` ports when DHCP misbehaves.

## LAN

**Mesh nodes and bridge loops.** Mesh access points that keep a wireless
backhaul while also cabled create a layer-2 loop
(`received packet on … with own address as source address` in `dmesg`).
Cable the satellite by the port the vendor intends for Ethernet backhaul
(often the WAN port), and enable STP on `br-lan` as a safety net.

**STP and lost SSH.** Enabling STP makes the bridge pass through
listening/learning (2 × `forward_delay`) after each reload. Services bound to
the `lan` interface (dropbear) may not come back; bind dropbear to all
interfaces and shorten `forward_delay`.

**Access points in router mode.** An AP left in its default router mode
double-NATs its clients onto a private subnet the gateway never sees. Bridge
it (WAN port into the AP's bridge, DHCP client on the bridge, its DHCP server
and NAT removed).

## DNS

**AdGuard Home on OpenWrt.** Its default work dir is under `/var` (RAM), so
filters and statistics vanish at reboot; move it to flash and keep the query
log in memory. Run the first-run wizard on a temporary port so dnsmasq keeps
serving DNS until the switch-over, then move dnsmasq to :54.

**Devices that bypass DNS filtering.** Many IoT devices query public
resolvers directly. An IDS on the segment shows it; redirect port 53 to the
router if filtering must be enforced.

## Security tooling

**Snort `pcap` capture delays alerts.** On quiet interfaces the pcap DAQ hands
packets over in batches; alerts appeared ~65 s late (IDS looked "dead").
`afpacket` delivers immediately.

**Testing Snort from the router itself.** Locally generated TCP/UDP is
captured before checksum offload fills in the checksum; Snort drops those
packets and rules don't match. Test from another host (ICMP works).

**`snort-mgr update-rules` fails** in some package versions (the command name
maps to a shell function with an underscore). Run `/usr/bin/snort-rules`.

**crowdsec + crowdsec-firewall-bouncer** both ship `/etc/config/crowdsec`;
installing both leaves apk reporting an error. Keep the engine's file and add
a `config bouncer` section (done in `00-packages.sh` / `50-security.sh`).

**Third-party LuCI packages.** Review before installing: install scripts,
rpcd backends, ACL scope, network endpoints, self-updaters. Pin versions and
verify SHA-256 (`fetch_verified` in `lib/common.sh`).

## IPv6 off

Disabling `net.ipv6.conf.all.disable_ipv6` also removes `::1`, breaking
services that listen on it. Removing the ULA prefix, prefix delegation,
RA/DHCPv6/NDP and `odhcpd`, and turning off AAAA answers in AdGuard, is enough
in practice. An old ULA address lingers as "deprecated" until it expires.
