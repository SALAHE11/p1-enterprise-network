# Low-level design (LLD)

Project 1, HQ switching. Updated topic by topic; this version covers Phase 1, topic 1 (VLANs and trunks).

## 1. VLANs
| VLAN ID | Name | Subnet | Gateway (topic 3) | Access ports |
|---|---|---|---|---|
| 10 | GUEST | 10.19.64.32/27 | 10.19.64.33 (core-sw) | acc-sw1 Ethernet4 |
| 100 | USERS | 10.18.0.0/22 | 10.18.0.1 (core-sw) | acc-sw1 Ethernet3, acc-sw2 Ethernet3 |

VLAN 1 carries no user traffic: it is not in any trunk's allowed list.

## 2. HQ switch ports
| Switch | Port | Mode | VLANs | Connects to |
|---|---|---|---|---|
| core-sw | Ethernet1 | trunk | 10,100 (native 1) | acc-sw1 Ethernet1 |
| core-sw | Ethernet2 | trunk | 10,100 (native 1) | acc-sw2 Ethernet1 |
| acc-sw1 | Ethernet1 | trunk | 10,100 (native 1) | core-sw Ethernet1 |
| acc-sw1 | Ethernet2 | trunk | 10,100 (native 1) | acc-sw2 Ethernet2 |
| acc-sw1 | Ethernet3 | access | 100 | user-pc1 |
| acc-sw1 | Ethernet4 | access | 10 | guest-kali |
| acc-sw2 | Ethernet1 | trunk | 10,100 (native 1) | core-sw Ethernet2 |
| acc-sw2 | Ethernet2 | trunk | 10,100 (native 1) | acc-sw1 Ethernet2 |
| acc-sw2 | Ethernet3 | access | 100 | user-pc2 |

## 3. Test hosts
| Host | Switch port | VLAN | Address | Default gateway |
|---|---|---|---|---|
| user-pc1 | acc-sw1 Ethernet3 | 100 | 10.18.0.2/22 | none yet (topic 3) |
| user-pc2 | acc-sw2 Ethernet3 | 100 | 10.18.0.3/22 | none yet (topic 3) |
| guest-kali | acc-sw1 Ethernet4 | 10 | 10.19.64.34/27 | none yet (topic 3) |

## 4. Spanning tree
- Mode: MSTP (EOS default), default priorities on all switches.
- Observed on 22 Nov: core-sw is not the root bridge. acc-sw1 Ethernet1 is blocked, so acc-sw1 reaches the rest of the network through acc-sw2.
- Planned (topic 2): core-sw becomes the root bridge.

## 5. Management
Each switch's Management0 is on the containerlab management network 172.20.20.0/24, out-of-band and separate from the user VLANs.

## 6. Configs
| Switch | File |
|---|---|
| core-sw | `configs/core-sw/core-sw.cfg` |
| acc-sw1 | `configs/acc-sw1/acc-sw1.cfg` |
| acc-sw2 | `configs/acc-sw2/acc-sw2.cfg` |

Exported with `docker exec clab-p1-enterprise-<switch> Cli -p 15 -c "show running-config"`.

## 7. Open items
- The native VLAN is still 1 (default) on all trunks. Hardening option: use an unused VLAN as the native VLAN on every trunk (to decide later).
