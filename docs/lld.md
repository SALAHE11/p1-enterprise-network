# Low-level design (LLD)

Project 1, HQ switching. Updated topic by topic; this version covers Phase 1, topic 1 (VLANs and trunks) and topic 2 (STP).

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
Mode: MSTP (EOS default), one instance (MST0) carrying all VLANs, so VLAN 10 and VLAN 100 share the same tree and the same blocked port.

### 4.1 Bridge priorities
| Switch | MST0 priority | System MAC | Role |
|---|---|---|---|
| core-sw | 4096 | 00:1c:73:7b:25:db | Root bridge |
| acc-sw1 | 32768 (default) | 00:1c:73:c0:10:f8 | |
| acc-sw2 | 32768 (default) | 00:1c:73:1e:70:04 | |

The core switch is the root on purpose: every access switch reaches it directly, and traffic between access switches crosses the core.

### 4.2 Port roles (all links up, verified 25 Nov with `show spanning-tree`)
| Switch | Port | Role | State |
|---|---|---|---|
| core-sw | Ethernet1, Ethernet2 | designated | forwarding |
| acc-sw1 | Ethernet1 | root | forwarding |
| acc-sw1 | Ethernet2 | **alternate** | **discarding** |
| acc-sw1 | Ethernet3, Ethernet4 | designated (edge) | forwarding |
| acc-sw2 | Ethernet1 | root | forwarding |
| acc-sw2 | Ethernet2 | designated | forwarding |
| acc-sw2 | Ethernet3 | designated (edge) | forwarding |

Why acc-sw1 Ethernet2 is blocked: both access switches are one link from the root, so the bridge ID decides; acc-sw2 has the lower MAC, so its end of the link is designated.

### 4.3 Host port protection
- `spanning-tree portfast` and `spanning-tree bpduguard enable` on every host port: acc-sw1 Ethernet3 and Ethernet4, acc-sw2 Ethernet3.
- PortFast: the port forwards immediately. BPDU Guard: the first BPDU received shuts the port down (errdisabled), so a switch plugged into a host port can't join or take over the tree.
- EOS treats ports that hear no BPDUs as edge ports by default (auto-edge), but that doesn't enable BPDU Guard, so it is configured explicitly.
- Never on trunks between switches: they must receive BPDUs.

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
- BPDU Guard attack test: needs a tool that forges BPDUs; planned for Phase 4 (attack validation from guest-kali).
- No backup root: if core-sw fails, the lowest MAC wins (acc-sw2). Option: give acc-sw2 priority 8192 as the planned backup root.
- Link-failure test not done yet: with core-sw ↔ acc-sw1 down, acc-sw1 Ethernet2 should become its root port.