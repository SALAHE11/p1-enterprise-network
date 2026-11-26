# Phase 1 notes: HQ core

## Topic 1: VLANs and trunks (19–22 Nov)

### What was built
- containerlab lab `p1-enterprise`: core-sw, acc-sw1 and acc-sw2 (cEOS 4.32.5.1M) in a triangle, plus three test hosts: user-pc1, user-pc2 and guest-kali.
- VLAN 10 (GUEST) and VLAN 100 (USERS) on all three switches. Links between switches are 802.1Q trunks allowing 10,100; host ports are access ports. Details in `docs/lld.md`.

### Tests and results
| Test | Expected | Result |
|---|---|---|
| No config: user-pc1 → user-pc2 | Works: every port starts in VLAN 1 | As expected: 3/3 replies |
| No config: guest-kali → user-pc1 | Fails: other subnet, no gateway | As expected: `Network is unreachable` |
| acc-sw2 not configured yet: user-pc1 → user-pc2 | Fails: VLAN 100 vs VLAN 1 | As expected: 100% loss |
| All configured: user-pc1 → user-pc2 | Works | As expected: 3/3 replies |
| All configured: user-pc1 → guest-kali | Fails: no inter-VLAN routing yet | As expected: `Network is unreachable` |
| `show interfaces trunk`, `show lldp neighbors` | Trunks up; neighbours match the port plan | As expected |
| Capture on acc-sw1 eth2 during a ping | Frames carry an 802.1Q tag with VLAN 100 | As expected: `captures/p1-8021q-trunk.pcap` |

### Observations
- STP (MSTP, the EOS default) blocks acc-sw1 Ethernet1, and core-sw is not the root bridge. A ping between user-pc1 and user-pc2 only crosses the acc-sw1–acc-sw2 trunk. To fix in topic 2.
- A tagged ping frame is 102 bytes; untagged it would be 98. The difference is the 4-byte 802.1Q tag.
- The capture shows ARP requests after the pings: Linux re-checks a stale neighbour entry with a unicast ARP request about 5 s after using it. Both hosts did it at the same moment.

### Problems and fixes
- The draft configs of the access switches had no trunk on Ethernet2 (acc-sw1 ↔ acc-sw2). STP blocks only one end of a loop, and the blocked link is the backup path, so both ends must be trunks. Fixed before deploy.
- clab file: a node name typo, missing `exec` address lines, and a /22 mask on guest-kali instead of /27. The file was first saved as `p1-entreprise.clab.yml`. Fixed in review.
- Config export: the first lines of the `Cli -c` output are not config; removed from the saved files.

### Lessons
- The subnet mask is checked on the host, before anything is sent ("direct or via my gateway?"). The VLAN is enforced by the switches. Without a router, two hosts talk only if both match.
- One VLAN = one subnet: a router picks the VLAN from the subnet.

## Topic 2: STP (22–25 Nov)

### What was built
- core-sw is the root bridge of MST0 (priority 4096).
- PortFast and BPDU Guard on the three host ports. Details in `docs/lld.md` section 4.

### Tests and predictions
| Test | Prediction | Result |
|---|---|---|
| Find the root from the port states seen on 22 Nov (core-sw Et1, Et2 forwarding; acc-sw1 Et1 blocked) | acc-sw2. acc-sw1 can't be root, because the root has no blocked port. core-sw can't either: acc-sw1 would use its direct link Et1 | Confirmed with `show spanning-tree` on acc-sw2: "This bridge is the root" |
| acc-sw1 port roles before the change | Et1 alternate, Et2 root, Et3 and Et4 designated | As predicted. Et3 and Et4 also showed `P2p Edge` (EOS auto-edge) |
| core-sw priority set to 4096 | core-sw root; acc-sw1 Et1 and acc-sw2 Et1 root ports; acc-sw1 Et2 alternate (same cost, acc-sw2 has the lower MAC) | As predicted |
| Ping user-pc1 → user-pc2 after the change | Path: acc-sw1 Et1 → core-sw → acc-sw2 Et1 (no longer the acc-sw1–acc-sw2 trunk) | Confirmed: `captures/p1-stp-core-root.pcap` on core-sw eth1 shows the pings (VLAN 100) |
| BPDUs in the same capture | Root = core-sw, cost 0 | `Root = 4096/0/00:1c:73:7b:25:db`, cost 0; the sender's bridge ID equals the root ID |
| PortFast and BPDU Guard in the saved configs | Present on acc-sw1 Et3, Et4 and acc-sw2 Et3 | Checked with `grep`. Attack test planned in Phase 4 |

### Security analysis: a rogue switch on a host port
- Without BPDU Guard, a switch plugged into acc-sw1 Ethernet4 that sends BPDUs with priority 0 becomes the root: STP believes any BPDU. Every switch rebuilds its tree, which means a short outage; repeated, it's a denial of service.
- With a second cable from the rogue switch to acc-sw2, the access switches' direct trunk and one core-sw port get blocked, so user-pc1 → user-pc2 traffic crosses the attacker's switch: a man-in-the-middle.
- Fix: BPDU Guard on every host port. A low priority on core-sw alone doesn't stop the attack, because the attacker can send priority 0 too. BPDU Filter (ignore BPDUs) would hide loops and risk a broadcast storm.

### Observations
- MST0 carries both VLANs, so they share one tree and one blocked port. Separate MSTP instances could block a different link per VLAN.
- A switch has one system MAC, used in the bridge ID, and one MAC per port, used as the source of frames, BPDUs included. BPDUs go to 01:80:c2:00:00:00, which switches never forward: each BPDU travels one link.
- EOS shows a path cost of 20000 per link here; the rule is the same (lowest total wins).
- In the 802.1Q tag, the 3-bit priority (PCP 0) is QoS and has nothing to do with the STP priority.
- After `destroy` and `deploy`, the saved switch configs and system MACs were kept; the test hosts got new MACs.

### Problems and fixes
- `spannig-tree` typo → `% Invalid input`. Use Tab to complete keywords.
- tcpdump with `-i Ethernet1` → tcpdump runs in Linux, where the port is `eth1`.
- `docker exec … sh running-config` ran the Linux shell. EOS commands need `Cli -p 15 -c "…"`.
- containerlab with a wrong `-t` path tried to download the file as a web address. Run from the repo root with `topology/p1-enterprise.clab.yml`.

### Lessons
- Port roles reveal the root: assume each switch is the root, then check against what you see.
- A root port always faces a designated port. On each link, the designated end is the switch closer to the root (lower own root cost), then the lower bridge ID.
- Choose the root on purpose (the core), and protect host ports with BPDU Guard.

## Topic 3: inter-VLAN routing (25–26 Nov)

### What was built
- core-sw routes between the VLANs: `ip routing`, `interface Vlan100` 10.18.0.1/22 and `interface Vlan10` 10.19.64.33/27. These are the hosts' default gateways.
- Each host's default route is in its clab `exec` lines (commit `f8e69d6`), so it comes back after a redeploy.
- Management VRF on core-sw: Management0 and its default route moved to VRF MGMT; SSH, eAPI, gNMI and NETCONF run in VRF MGMT only. Details in `docs/lld.md` sections 5 and 6.

### Tests and predictions
| Test | Expected | Result |
|---|---|---|
| user-pc1 → guest-kali | Works, `ttl=63`: core-sw lowers the TTL once when it forwards | As expected: `ttl=63` |
| guest-kali → 172.20.20.4 (core-sw's Management0), before the fix | Must fail: the guest VLAN must never reach a management address | Replied with `ttl=64`: core-sw answered for itself. This is the management leak (security analysis below) |
| Capture on core-sw eth1, filter `vlan and icmp`, during `ping -c 3` user-pc1 → guest-kali | 4 frames per ping (table below) | 12 frames: `captures/p1-intervlan-routed-ping.pcap`. Prediction 6/8: missed the destination MAC going down (guest-kali, not user-pc1) and the TTL going down (63) |
| `ip route` on the three hosts after `destroy` + `deploy` | `default via` the gateway on each host | As expected |

What the capture shows for each ping (core-sw eth1 is the trunk to acc-sw1):

| Frame | Direction | VLAN | Source MAC → destination MAC | TTL |
|---|---|---|---|---|
| Request | acc-sw1 → core-sw | 100 | user-pc1 → core-sw | 64 |
| Same request, routed | core-sw → acc-sw1 | 10 | core-sw → guest-kali | 63 |
| Reply | acc-sw1 → core-sw | 10 | guest-kali → core-sw | 64 |
| Same reply, routed | core-sw → acc-sw1 | 100 | core-sw → user-pc1 | 63 |

### Security analysis: the management leak
- **Cause:** Management0 was in VRF default, the same routing table as Vlan100 and Vlan10, with `ip routing` on. So the connected route 172.20.20.0/24 and containerlab's default route via 172.20.20.1 were in the table the VLANs use, and 172.20.20.4 counted as one of core-sw's own addresses for packets from the VLANs.
- **Leak 1, guest VLAN → switch management (proven 26 Nov):** from guest-kali, `nmap 172.20.20.4` found 22 and 443 open (21 closed, 979 filtered). `ssh admin@172.20.20.4` with containerlab's default `admin/admin` gave the CLI, and `enable` asked for no password: full admin rights from the guest VLAN. core-sw recorded it: `Last login: Thu Nov 26 11:25:21 2026 from 10.19.64.34`. `ssh admin@10.19.64.33` (the guest gateway) worked too: a service listens on every own address of its VRF.
- **Leak 2, user traffic out Management0 (explained, not captured):** traffic from the VLANs to unknown destinations matched the default route via 172.20.20.1 and left through Management0 to the laptop. The laptop forwarded it out the Wi-Fi untranslated (Docker's MASQUERADE only matches `-s 172.20.20.0/24`), so lab addresses reached the home network and no reply came back.
- **Path B, a host using its own management interface (checked, closed):** the hosts have no `eth0` (`network-mode: none`); `ip route get 172.20.20.4` gives `via` the gateway on all three.
- **The fix (core-sw), in an order that never cuts the laptop off:**
  1. `vrf instance MGMT`; SSH and eAPI enabled in VRF MGMT.
  2. `interface Management0` → `vrf MGMT`. EOS removed its IPv4 and IPv6 addresses, so `ip address 172.20.20.4/24` again (IPv6 left off).
  3. `ip route vrf MGMT 0.0.0.0/0 172.20.20.1`; the old default route and the stale `ipv6 route ::/0 3fff:172:20:20::1` removed.
  4. `management ssh` → `vrf default` → `shutdown`.
- **Second finding (26 Nov afternoon):** a scan of both SVIs from guest-kali still found NETCONF (TCP 830) and gNMI (TCP 6030) open: containerlab's default cEOS config enables them in VRF default. NETCONF reset the connection (it runs over SSH, already shut in VRF default); gNMI was probably usable (no gNMI client on the hosts to prove it). Fixed by moving both into VRF MGMT (`transport … default` → `vrf MGMT`).
- Still open: GUEST ↔ USERS traffic is routed. The guest ACL comes in Phase 2.

Retest after the fix (26 Nov, all passed):

| Test | Must give | Result |
|---|---|---|
| guest-kali → ping 172.20.20.4 | `Network unreachable` | Passed |
| guest-kali → `ssh admin@10.19.64.33` | `Connection refused` | Passed |
| guest-kali → `nmap` ports 22, 443, 830, 6030 on 10.19.64.33 and 10.18.0.1 | Nothing open | Passed: closed or filtered |
| user-pc2 → ping 8.8.8.8 | Fails: no default route in VRF default | Passed |
| user-pc1 → ping guest-kali | Still works, `ttl=63` | Passed |
| Laptop → `ssh admin@172.20.20.4`, ports 443, 830, 6030 | Work | Passed |
| core-sw `show ip route` | Only the two VLAN routes | Passed |
| core-sw `show ip route vrf MGMT` | C 172.20.20.0/24, S 0.0.0.0/0 via 172.20.20.1 | Passed |

### Observations
- Both SVIs use core-sw's system MAC (00:1c:73:7b:25:db). No conflict: a MAC only has to be unique inside one VLAN, and MAC tables are kept per VLAN.
- user-pc1 and guest-kali are both on acc-sw1, yet the routed ping crosses the acc-sw1–core-sw trunk twice: up to the gateway in one VLAN, back down in the other.
- Routing took about 0.6 ms (request at 0.000000 s, routed copy at 0.000590 s).
- Wireshark marks each first copy of a request "no response found": the capture sees every packet twice; nothing was lost.
- Three different errors: `Network unreachable` = core-sw has no route to the address; `Connection refused` = the device was reached, but nothing listens on that port; connection reset on port 830 = the port accepted the connection, but no SSH server was behind it.
- `show management ssh` never listed VRF MGMT, even with SSH working there. A login from the laptop is the real proof.
- core-sw's own Internet is now in VRF MGMT: `ping 8.8.8.8` fails, `ping vrf MGMT 8.8.8.8` works.

### Problems and fixes
- 25 Nov: `deploy` failed with "network namespace is not available (status=Stopped)". acc-sw1, from an earlier deploy, had crashed (`systemd-journald` watchdog timeout; cause not confirmed). Fix: `destroy` + `deploy` without `--cleanup`; the saved configs were kept.
- EOS removed Management0's addresses when it moved to VRF MGMT. Fix: set the IPv4 address again right after `vrf MGMT`.
- Two commits with the same message (`c1b2a13`, `2661222`): the second only removed the export's first lines. Clean the export before `git add`.
- The first fix only covered SSH and eAPI. gNMI and NETCONF were found open by a scan later the same day (security analysis).

### Lessons
- One shared VRF caused both leaks: with management and users in one routing table, each side can reach the other.
- "Is it mine?" comes before the routing table, per VRF: a router answers for every own address of the VRF the packet arrived in. Moving Management0 isn't enough; turn the services off in VRF default too.
- Isolation is enforced by the network, not by the host: the fix is in core-sw's VRFs, not in a host route or a host firewall.
- After a management fix, scan every management port (22, 80, 443, 830, 6030, 8080) on every own address, from a host in each VLAN.
- Routing looks at the destination, NAT at the source: Leak 2's packets were forwarded, but never translated.
- Change the management path in a safe order: services in the new VRF first, then move the interface.
- A router lowers the TTL when it forwards a packet, not when the packet is for itself: 64 = core-sw answered, 63 = forwarded once.
