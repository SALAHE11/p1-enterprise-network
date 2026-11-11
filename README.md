# Secure Multi-Site Enterprise Network

A lab-built network for a fictional company with a headquarters, a branch office and a remote worker.
Goal: network segmentation with two firewalls, site-to-site and remote-access VPNs, and automated testing, all on one laptop.

**Built with:** containerlab, Arista cEOS, OPNsense, FortiGate VM, KVM.

## Status
Phase 0 (lab setup) in progress. Target for v1.0: February 2027.

## Repository layout
- `topology/`: lab topology, bridge script, VM definitions
- `images/`: Dockerfiles for custom lab nodes
- `configs/`: device configurations and backups
- `automation/`: Ansible playbooks and tests
- `docs/`: design, IP plan, test plan and reports
- `captures/`: Wireshark captures
