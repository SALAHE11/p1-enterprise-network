#!/usr/bin/env bash
#This is a script that will create the 5 profiles for the bridges on the topology, to run is use sudo ./topology/bridges-up.sh
set -euo pipefail
BRIDGES=(br-wan br-lan br-dmz br-fgt br-srv)
if [[ $EUID -ne 0 ]]; then
echo "Error not root : $0, use sudo" >&2;
exit 1;
fi
for bridge in "${BRIDGES[@]}"; do
    if ! nmcli connection show "$bridge" >/dev/null 2>&1; then
        nmcli connection add type bridge ifname "$bridge" con-name "$bridge" bridge.stp no ipv4.method  disabled ipv6.method disabled >/dev/null;
        echo "$bridge: profile created."
    fi
    state=$(nmcli -g GENERAL.STATE connection show "$bridge" 2>/dev/null || true)
    if [[ "activated" == "$state" ]]; then
        echo "$bridge: already active"
    else
        nmcli connection up "$bridge" >/dev/null;
        echo "$bridge: activated."
    fi
done



