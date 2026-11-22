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
