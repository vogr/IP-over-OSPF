#!/usr/bin/env bash
set -xu

# A good ressource on Linux Network Namespaces :
# https://blog.scottlowe.org/2013/09/04/introducing-linux-network-namespaces/

: <<'END_COMMENT'

This script configures the machines on left, mid, and right
for a demonstrations of mbird.

IP forwarding is enabled on left and right, NAT is
enabled on right. Routes are set up so that:
- left has right as its default gateway
- right has root as its default gateway
- root may NAT packets from both left and right to the Internet

To access the Internet from left:
- run an ospf router on mid, e.g. bird: sudo ./setup.sh run mid
- run the modified ospf router on left and right : sudo ./setup run mid; sudo ./setup.sh run right
- you may now access the Internet from left! (e.g: ping 8.8.8.8)

Ethernet frames sent from the left are added to the LSA database of the modified bird router on the left 
using a tap device ; the OSPF protocol takes care of propagating this data to mid and then to right.
When these frames arrive in the LSA database on right, they are sent to a tap device and can be forwarded
to the main namespace. The IP addresses in these packets get through NAT before being sent to the Internet.

Note : DNS resolution does not work yet.

END_COMMENT

main () {
if [[ $# -lt 1 ]]; then 
  printf "Error: setup.sh requires one argument (up, down, or run)\n"
  exit 1
fi

if [[ "$1" == "up" ]]; then
    if [[ "$2" == "left" ]]; then
      systemctl stop NetworkManager

      ip addr add fe80::1/64 dev enp0s31f6

      ip tuntap add name tap0 mode tap
      ip addr add 192.168.10.1/24 dev tap0
      ip link set up dev tap0

      sysctl -w net.ipv6.conf.all.forwarding=1 &&
      sysctl -w net.ipv4.ip_forward=1

      ip route add 0.0.0.0/0 via 192.168.10.3

      #TODO: ajouter adresse IP à l'adaptateur ethernet.
    elif [[ "$2" == "right" ]]; then
      ip addr add fe80::4/64 dev enp0s31f6

      ip tuntap add name tap0 mode tap
      ip addr add 192.168.10.3/24 dev tap0
      ip link set up dev tap0

      # Enable forwarding between interfaces
      sysctl -w net.ipv6.conf.all.forwarding=1 &&
      sysctl -w net.ipv4.ip_forward=1

      # Enable NAT
      iptables -A FORWARD -o wlp2s0 -i tap0 -j ACCEPT
      iptables -A FORWARD -i wlp2s0 -o tap0 -j ACCEPT
      iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o wlp2s0 -j MASQUERADE
      #TODO: ajouter adresse IP à l'adaptateur ethernet.
    elif [[ "$2" == "mid" ]]; then
      systemctl stop NetworkManager
      ip addr add fe80::2/64 dev enx503eaae32993
      ip addr add fe80::3/64 dev enx000ec6d9ad89
    else
      printf "Parameter not recognized %s" "$2"
    fi;

elif [[ $1 == "down" ]]; then
  ip link del dev tap0
elif [[ $1 == "run" ]]; then
  if  [[ "$2" == "mid" ]]; then
    "./bird-2.0.7/bird" -d -s "bird_mid.ctl" -c "real/bird_mid.conf";
  elif [[ "$2" == "left" || "$2" == "right" ]]; then
    "./mbird/bird" -d -s "bird_$2.ctl" -c "real/bird_$2.conf";
  fi
fi
}

main "$@"; exit
