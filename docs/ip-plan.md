# IP addressing plan (v1)

Status: approved on 18 Nov 2026. See also: [High-Level Design](hld.md).

## At a glance

| Item | Value |
|---|---|
| All internal ranges (summary) | 10.18.0.0/15 (10.18.0.0 to 10.19.255.255) |
| Public ISP links | 203.0.113.0/28: four /30 links from the RFC 5737 documentation range |
| VLANs | USERS = 100, GUEST = 10 |
| Gateways | Always the first usable address of the subnet |

## Sizing assumptions

Subnets are sized for the company's planned size plus the gateway, not for the lab. The lab builds only one or two test hosts per zone.

| Item | Now | Planned |
|---|---|---|
| HQ employees | 300 | 750 |
| Branch employees | 50 | 150 |
| Printers (one per 25 employees) | 12 at HQ, 2 at the branch | 30 at HQ, 6 at the branch |
| GUEST devices (visitors only) | – | 20 at the same time |
| Internal servers | 2 | 10 |
| DMZ servers | 1 | 4 |
| Remote workers connected at the same time | – | 24 |

## Subnets

Placed biggest first, so each one starts on its own block boundary.

| Zone | VLAN | Subnet | Usable | Needed | Gateway | Static addresses |
|---|---|---|---|---|---|---|
| USERS (HQ) | 100 | 10.18.0.0/22 | 1022 | 781 (750 computers + 30 printers + gateway) | core-sw 10.18.0.1 | None (DHCP) |
| Branch LAN | – | 10.19.0.0/24 | 254 | 157 (150 computers + 6 printers + gateway) | br-rtr 10.19.0.1 | br-pc 10.19.0.2 |
| OpenVPN pool | – | 10.19.64.0/27 | 30 | 25 (24 remote workers + the OpenVPN server) | – | – |
| GUEST (HQ) | 10 | 10.19.64.32/27 | 30 | 21 (20 devices + gateway) | core-sw 10.19.64.33 | None (DHCP) |
| Server zone | – | 10.19.64.64/28 | 14 | 11 (10 servers + gateway) | FortiGate port3 10.19.64.65 | srv-dns 10.19.64.66, srv-app 10.19.64.67 |
| DMZ | – | 10.19.64.80/29 | 6 | 5 (4 servers + gateway) | OPNsense DMZ 10.19.64.81 | dmz-web 10.19.64.82 |

Hosts in USERS and GUEST get their addresses by DHCP from srv-dns, through the relay on core-sw. The DHCP ranges are set in the LLD (Phase 1).

## Point-to-point links (/30)

| Link | Subnet | First address | Second address |
|---|---|---|---|
| core-sw ↔ OPNsense (OSPF area 0) | 10.19.64.88/30 | core-sw 10.19.64.89 | OPNsense LAN 10.19.64.90 |
| core-sw ↔ FortiGate | 10.19.64.92/30 | core-sw 10.19.64.93 | FortiGate port2 10.19.64.94 |
| IPsec tunnel (VTI) | 10.19.64.96/30 | OPNsense 10.19.64.97 | br-rtr 10.19.64.98 |

## Public ISP links (/30)

| Link | Subnet | isp-rtr | Other end |
|---|---|---|---|
| HQ WAN | 203.0.113.0/30 | 203.0.113.1 | OPNsense WAN 203.0.113.2 |
| Branch WAN | 203.0.113.4/30 | 203.0.113.5 | br-rtr WAN 203.0.113.6 |
| Remote worker | 203.0.113.8/30 | 203.0.113.9 | remote-pc 203.0.113.10 |
| Outside client | 203.0.113.12/30 | 203.0.113.13 | ext-host 203.0.113.14 |

## Free space for growth

| Range | Free for |
|---|---|
| 10.18.4.0 to 10.18.255.255 | More HQ subnets or VLANs |
| 10.19.1.0 to 10.19.63.255 | Branch growth, or more branches |
| 10.19.64.100 to 10.19.255.255 | More small subnets and links |

## Why it looks like this

- **One summary (10.18.0.0/15).** The FortiGate trial allows only three static routes. One route through core-sw covers every internal range, and the default route through port1 covers the rest. One summary also keeps the rules short: one "internal networks" object in the firewalls, and one line in the guest ACL.
- **10.x, not 172.x or 192.168.x.** Docker's default address pools cover 172.17.0.0 to 172.31.255.255 and 192.168.0.0/16. Any new Docker network on the lab host would land on top of those ranges.
- **The tunnel /30 is inside the summary.** Packets that OPNsense or br-rtr send themselves through the tunnel carry a tunnel address. Replies to them must route back inside, not out the FortiGate's default route.
- **The DMZ is a /29.** Four public servers is already a generous estimate, so 6 usable addresses are enough.
- **The small ranges start at 10.19.64.0.** This leaves 10.19.0.0 to 10.19.63.255 free, so the branch can grow without renumbering.
- **The public links use 203.0.113.0/24 (RFC 5737).** These documentation addresses never appear on the real Internet, so the lab never borrows a real company's addresses.

## Ranges to avoid on the lab host

These ranges are already used on the machine that runs the lab, so the plan stays clear of them.

| Range | Used by |
|---|---|
| 172.17.0.0/16 | Docker's default network (`docker0`) |
| 172.17.0.0 to 172.31.255.255, and 192.168.0.0/16 | Docker's default address pools (future Docker networks) |
| 172.20.20.0/24 | containerlab's management network (the switches' Ma0 ports) |
| 192.168.122.0/24 | libvirt's default network `virbr0` (firewall management) |
| Your own LAN or Wi-Fi range | The host's network connection (check it with `ip -br addr`) |
