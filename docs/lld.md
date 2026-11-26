# Low-level design (LLD)

Project 1, HQ switching and routing. Updated topic by topic; this version covers Phase 1, topics 1 (VLANs and trunks), 2 (STP) and 3 (inter-VLAN routing).

## 1. VLANs
| VLAN ID | Name | Subnet | Gateway (core-sw SVI) | Access ports |
|---|---|---|---|---|
| 10 | GUEST | 10.19.64.32/27 | 10.19.64.33 (Vlan10) | acc-sw1 Ethernet4 |
| 100 | USERS | 10.18.0.0/22 | 10.18.0.1 (Vlan100) | acc-sw1 Ethernet3, acc-sw2 Ethernet3 |

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
| user-pc1 | acc-sw1 Ethernet3 | 100 | 10.18.0.2/22 | 10.18.0.1 |
| user-pc2 | acc-sw2 Ethernet3 | 100 | 10.18.0.3/22 | 10.18.0.1 |
| guest-kali | acc-sw1 Ethernet4 | 10 | 10.19.64.34/27 | 10.19.64.33 |

- Address and default route come from each host's `exec` lines in `topology/p1-enterprise.clab.yml` (address first, then `ip route add default via <gateway>`), so they come back after every `deploy`. Static until DHCP (topic 4).
- The hosts have no management interface (`network-mode: none`): `eth1` is their only interface, so everything they send goes through their gateway.

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

## 5. Routing and management VRF (core-sw)
core-sw routes between the VLANs (`ip routing`, one SVI per VLAN). Its management port is in a separate VRF, so the VLANs can't reach it.

### 5.1 VRFs
| VRF | Interfaces | Routing table | Forwards between its interfaces |
|---|---|---|---|
| default | Vlan100 10.18.0.1/22, Vlan10 10.19.64.33/27 | C 10.18.0.0/22, C 10.19.64.32/27; no default route | Yes (`ip routing`) |
| MGMT | Management0 172.20.20.4/24 | C 172.20.20.0/24, S 0.0.0.0/0 via 172.20.20.1 (the laptop) | No (`no ip routing vrf MGMT`, added by EOS): only core-sw's own traffic |

- A VRF is a separate routing table with its own list of own addresses; each interface belongs to exactly one VRF. A packet that arrives on an SVI is looked up in VRF default only, so 172.20.20.0/24 doesn't exist for the VLANs.
- Why: with Management0 in VRF default, the guest VLAN could log in to core-sw, and user traffic followed containerlab's default route out Management0 (`docs/phase-notes/phase-1.md`, topic 3).
- core-sw's own Internet access is in VRF MGMT: `ping vrf MGMT 8.8.8.8`.
- The VLANs have no Internet yet: their default route will come from OPNsense by OSPF (later in Phase 1).

### 5.2 Management services on core-sw
| Service | Port | VRF MGMT | VRF default | Config |
|---|---|---|---|---|
| SSH | TCP 22 | on | off | `management ssh` → `vrf MGMT` → `no shutdown`; `vrf default` → `shutdown` |
| eAPI (HTTPS) | TCP 443 | on | off (443 refused on the SVIs, 26 Nov) | `management api http-commands` → `vrf MGMT` → `no shutdown`; no `vrf default` line (open item) |
| gNMI | TCP 6030 | on | off | `management api gnmi` → `transport grpc default` → `vrf MGMT` |
| NETCONF | TCP 830 | on | off | `management api netconf` → `transport ssh default` → `vrf MGMT` |

- A service listens on every own address of its VRF. Turning it off in VRF default closes it on both SVIs.
- In `transport grpc default` and `transport ssh default`, `default` is the transport's name, not the VRF.
- IPv6 management is off: no IPv6 address on Management0 and no IPv6 default route.
- Checked 26 Nov: from guest-kali, ports 22, 443, 830 and 6030 on 10.19.64.33 and 10.18.0.1 are closed or filtered (`nmap`); from the laptop, SSH, 443, 830 and 6030 on 172.20.20.4 work.

## 6. Management
| Switch | Management0 | VRF | Default route | Management services |
|---|---|---|---|---|
| core-sw | 172.20.20.4/24 | MGMT | 0.0.0.0/0 via 172.20.20.1, in VRF MGMT | VRF MGMT only (section 5.2) |
| acc-sw1 | 172.20.20.2/24 | default | 0.0.0.0/0 via 172.20.20.1 | containerlab defaults (SSH, eAPI, gNMI, NETCONF) in VRF default |
| acc-sw2 | 172.20.20.3/24 | default | 0.0.0.0/0 via 172.20.20.1 | same as acc-sw1 |

- Management is out-of-band only (design decision 16): Management0 sits on the containerlab management network 172.20.20.0/24 and is managed from the laptop (`ssh admin@172.20.20.4`).
- The access switches keep Management0 in VRF default for now. The VLANs can't reach them: they have no `ip routing` and no SVI, and core-sw has no route to 172.20.20.0/24 in VRF default. They get the management VRF in Phase 3, with the automation template.

## 7. Configs
| Switch | File |
|---|---|
| core-sw | `configs/core-sw/core-sw.cfg` |
| acc-sw1 | `configs/acc-sw1/acc-sw1.cfg` |
| acc-sw2 | `configs/acc-sw2/acc-sw2.cfg` |

Exported with `docker exec clab-p1-enterprise-<switch> Cli -p 15 -c "show running-config"`.

## 8. Open items
- The native VLAN is still 1 (default) on all trunks. Hardening option: use an unused VLAN as the native VLAN on every trunk (to decide later).
- BPDU Guard attack test: needs a tool that forges BPDUs; planned for Phase 4 (attack validation from guest-kali).
- No backup root: if core-sw fails, the lowest MAC wins (acc-sw2). Option: give acc-sw2 priority 8192 as the planned backup root.
- Link-failure test not done yet: with core-sw ↔ acc-sw1 down, acc-sw1 Ethernet2 should become its root port.
- Guest ACL (Phase 2): core-sw routes GUEST ↔ USERS today (user-pc1 → guest-kali works, `ttl=63`). Planned: ACL on Vlan10 that permits DNS to OPNsense, denies all internal ranges and permits the rest.
- Management VRF on acc-sw1 and acc-sw2: Phase 3, with the automation template.
- eAPI in VRF default: no explicit `vrf default` → `shutdown` line. 443 is refused on the SVIs, but confirm with the `VRFs:` line of `show management api http-commands`, or add the line.
- SSH service ACL (Phase 2 hardening, audit item 6): decide whether it is still needed now that SSH runs in VRF MGMT only.
- Review `default-control-plane-acl` (`show ip access-lists default-control-plane-acl`): it probably explains the `filtered` ports in the nmap results.
- containerlab's default login (`admin/admin`) is still in use and `enable` asks for no password: replace with local admin accounts in the Phase 2 hardening.
EOFcd /data/projects/p1-enterprise-network
cat > docs/lld.md << 'EOF'
# Low-level design (LLD)

Project 1, HQ switching and routing. Updated topic by topic; this version covers Phase 1, topics 1 (VLANs and trunks), 2 (STP) and 3 (inter-VLAN routing).

## 1. VLANs
| VLAN ID | Name | Subnet | Gateway (core-sw SVI) | Access ports |
|---|---|---|---|---|
| 10 | GUEST | 10.19.64.32/27 | 10.19.64.33 (Vlan10) | acc-sw1 Ethernet4 |
| 100 | USERS | 10.18.0.0/22 | 10.18.0.1 (Vlan100) | acc-sw1 Ethernet3, acc-sw2 Ethernet3 |

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
| user-pc1 | acc-sw1 Ethernet3 | 100 | 10.18.0.2/22 | 10.18.0.1 |
| user-pc2 | acc-sw2 Ethernet3 | 100 | 10.18.0.3/22 | 10.18.0.1 |
| guest-kali | acc-sw1 Ethernet4 | 10 | 10.19.64.34/27 | 10.19.64.33 |

- Address and default route come from each host's `exec` lines in `topology/p1-enterprise.clab.yml` (address first, then `ip route add default via <gateway>`), so they come back after every `deploy`. Static until DHCP (topic 4).
- The hosts have no management interface (`network-mode: none`): `eth1` is their only interface, so everything they send goes through their gateway.

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

## 5. Routing and management VRF (core-sw)
core-sw routes between the VLANs (`ip routing`, one SVI per VLAN). Its management port is in a separate VRF, so the VLANs can't reach it.

### 5.1 VRFs
| VRF | Interfaces | Routing table | Forwards between its interfaces |
|---|---|---|---|
| default | Vlan100 10.18.0.1/22, Vlan10 10.19.64.33/27 | C 10.18.0.0/22, C 10.19.64.32/27; no default route | Yes (`ip routing`) |
| MGMT | Management0 172.20.20.4/24 | C 172.20.20.0/24, S 0.0.0.0/0 via 172.20.20.1 (the laptop) | No (`no ip routing vrf MGMT`, added by EOS): only core-sw's own traffic |

- A VRF is a separate routing table with its own list of own addresses; each interface belongs to exactly one VRF. A packet that arrives on an SVI is looked up in VRF default only, so 172.20.20.0/24 doesn't exist for the VLANs.
- Why: with Management0 in VRF default, the guest VLAN could log in to core-sw, and user traffic followed containerlab's default route out Management0 (`docs/phase-notes/phase-1.md`, topic 3).
- core-sw's own Internet access is in VRF MGMT: `ping vrf MGMT 8.8.8.8`.
- The VLANs have no Internet yet: their default route will come from OPNsense by OSPF (later in Phase 1).

### 5.2 Management services on core-sw
| Service | Port | VRF MGMT | VRF default | Config |
|---|---|---|---|---|
| SSH | TCP 22 | on | off | `management ssh` → `vrf MGMT` → `no shutdown`; `vrf default` → `shutdown` |
| eAPI (HTTPS) | TCP 443 | on | off (443 refused on the SVIs, 26 Nov) | `management api http-commands` → `vrf MGMT` → `no shutdown`; no `vrf default` line (open item) |
| gNMI | TCP 6030 | on | off | `management api gnmi` → `transport grpc default` → `vrf MGMT` |
| NETCONF | TCP 830 | on | off | `management api netconf` → `transport ssh default` → `vrf MGMT` |

- A service listens on every own address of its VRF. Turning it off in VRF default closes it on both SVIs.
- In `transport grpc default` and `transport ssh default`, `default` is the transport's name, not the VRF.
- IPv6 management is off: no IPv6 address on Management0 and no IPv6 default route.
- Checked 26 Nov: from guest-kali, ports 22, 443, 830 and 6030 on 10.19.64.33 and 10.18.0.1 are closed or filtered (`nmap`); from the laptop, SSH, 443, 830 and 6030 on 172.20.20.4 work.

## 6. Management
| Switch | Management0 | VRF | Default route | Management services |
|---|---|---|---|---|
| core-sw | 172.20.20.4/24 | MGMT | 0.0.0.0/0 via 172.20.20.1, in VRF MGMT | VRF MGMT only (section 5.2) |
| acc-sw1 | 172.20.20.2/24 | default | 0.0.0.0/0 via 172.20.20.1 | containerlab defaults (SSH, eAPI, gNMI, NETCONF) in VRF default |
| acc-sw2 | 172.20.20.3/24 | default | 0.0.0.0/0 via 172.20.20.1 | same as acc-sw1 |

- Management is out-of-band only (design decision 16): Management0 sits on the containerlab management network 172.20.20.0/24 and is managed from the laptop (`ssh admin@172.20.20.4`).
- The access switches keep Management0 in VRF default for now. The VLANs can't reach them: they have no `ip routing` and no SVI, and core-sw has no route to 172.20.20.0/24 in VRF default. They get the management VRF in Phase 3, with the automation template.

## 7. Configs
| Switch | File |
|---|---|
| core-sw | `configs/core-sw/core-sw.cfg` |
| acc-sw1 | `configs/acc-sw1/acc-sw1.cfg` |
| acc-sw2 | `configs/acc-sw2/acc-sw2.cfg` |

Exported with `docker exec clab-p1-enterprise-<switch> Cli -p 15 -c "show running-config"`.

## 8. Open items
- The native VLAN is still 1 (default) on all trunks. Hardening option: use an unused VLAN as the native VLAN on every trunk (to decide later).
- BPDU Guard attack test: needs a tool that forges BPDUs; planned for Phase 4 (attack validation from guest-kali).
- No backup root: if core-sw fails, the lowest MAC wins (acc-sw2). Option: give acc-sw2 priority 8192 as the planned backup root.
- Link-failure test not done yet: with core-sw ↔ acc-sw1 down, acc-sw1 Ethernet2 should become its root port.
- Guest ACL (Phase 2): core-sw routes GUEST ↔ USERS today (user-pc1 → guest-kali works, `ttl=63`). Planned: ACL on Vlan10 that permits DNS to OPNsense, denies all internal ranges and permits the rest.
- Management VRF on acc-sw1 and acc-sw2: Phase 3, with the automation template.
- eAPI in VRF default: no explicit `vrf default` → `shutdown` line. 443 is refused on the SVIs, but confirm with the `VRFs:` line of `show management api http-commands`, or add the line.
- SSH service ACL (Phase 2 hardening, audit item 6): decide whether it is still needed now that SSH runs in VRF MGMT only.
- Review `default-control-plane-acl` (`show ip access-lists default-control-plane-acl`): it probably explains the `filtered` ports in the nmap results.
- containerlab's default login (`admin/admin`) is still in use and `enable` asks for no password: replace with local admin accounts in the Phase 2 hardening.
