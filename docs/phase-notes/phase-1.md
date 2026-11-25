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