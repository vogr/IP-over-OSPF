#!/usr/bin/env bash
set -xu

# A good ressource on Linux Network Namespaces :
# https://blog.scottlowe.org/2013/09/04/introducing-linux-network-namespaces/

: <<'END_COMMENT'

This script creates three network namespaces (ns_left, ns_mid, ns_right) and
creates virtual ethernet pairs to connect:
- left to mid
- mid to right
- right to the root namespace

It creates tap devices:
- tap0 with address 192.168.1.1 in left
- tap0 with address 192.168.1.3 in right

IP forwarding is enabled in ns_left and in the root namespace, NAT is
enabled in the root namespace and routes are set up so that:
- left has right as its default gateway
- right has root as its default gateway
- root may NAT packets from both left and right to the Internet

To access the Internet from left:
- run an ospf router on mid, e.g. bird: sudo ./setup.sh run mid
- run the modified ospf router on left and right : sudo ./setup run mid; sudo ./setup.sh run right
- open a shell in left: sudo ./setup.sh bash left
- in this shell, you may now access the Internet! (e.g: ping 8.8.8.8)

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

if [[ $1 == "up" ]]; then
  # Create the 3 network namespaces, and activate loopback on each
  for SIDE in "left" "mid" "right"; do
    ip netns add ns_$SIDE
    ip netns exec ns_$SIDE bash -c "ip link set dev lo up"
  done;
  # Deal with namespaces for the modified bird routers (left and right)
  for SIDE in "left" "right"; do
    # Create virtual ethernet pairs
    ip link add veth_${SIDE}_self type veth peer name veth_${SIDE}_mid
    # Assigns virtual ethernets to namespace
    ip link set dev veth_${SIDE}_self netns ns_$SIDE
    ip link set dev veth_${SIDE}_mid netns ns_mid


    # Create tap interface.
    ip netns exec ns_${SIDE} ip tuntap add name tap0 mode tap

    # Activer les interfaces virtuelles veth
    # et activer le forwarding ipv4 et ipv6
    # pour left et right
    ip netns exec ns_$SIDE sh -c \
      "ip link set dev veth_${SIDE}_self up &&
      sysctl -w net.ipv6.conf.all.forwarding=1 &&
      sysctl -w net.ipv4.ip_forward=1"
  done

  # Activer les interfaces virtuelles veth
  ip netns exec ns_mid sh -c \
   "ip link set dev veth_left_mid up &&
    ip link set dev veth_right_mid up"

  ip netns exec ns_left bash -c \
    "ip addr add 192.168.1.1/24 dev tap0 &&
    ip link set up dev tap0 &&

    ip route add 0.0.0.0/0 via 192.168.1.3"

  ip link add veth_main_self type veth peer name veth_main_right
  ip link set veth_main_right netns ns_right

  ip netns exec ns_right bash -c \
    "ip addr add 192.168.1.3/24 dev tap0 &&
    ip link set up dev tap0 &&
    
    ip addr add 192.168.2.1/24 dev veth_main_right &&
    ip link set up dev veth_main_right &&

    ip route add 0.0.0.0/0 via 192.168.2.2"

  ip addr add 192.168.2.2/24 dev veth_main_self
  ip link set up dev veth_main_self

  # Enable IP forwarding in main namespace
  sysctl -w net.ipv6.conf.all.forwarding=1 &&
  sysctl -w net.ipv4.ip_forward=1

  # Enable forwarding between interfaces
  iptables -A FORWARD -o wlp2s0 -i veth_main_self -j ACCEPT
  iptables -A FORWARD -i wlp2s0 -o veth_main_self -j ACCEPT

  # Enable NAT
  iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -o wlp2s0 -j MASQUERADE
  iptables -t nat -A POSTROUTING -s 192.168.2.0/24 -o wlp2s0 -j MASQUERADE

  # Add route from root namespace to ns_left
  ip route add 192.168.1.0/24 via 192.168.2.1

elif [[ $1 == "down" ]]; then
  for SIDE in "left" "right"; do
    ip link delete dev veth_${SIDE}_self
  done;
  for SIDE in "left" "mid" "right"; do
    ip netns delete ns_$SIDE
  done
elif [[ $1 == "run" ]]; then
  if  [[ "$2" == "mid" ]]; then
    ip netns exec "ns_mid" "./bird-2.0.7/bird" -d -s "bird_mid.ctl" -c "virtual/bird_mid.conf";
  elif [[ "$2" == "left" || "$2" == "right" ]]; then
    ip netns exec "ns_$2" "./mbird/bird" -d -s "bird_$2.ctl" -c "virtual/bird_$2.conf";
  fi
elif [[ $1 == "bash" ]]; then
  if [[ $# -lt 2 ]]; then 
    printf "\`bash\` requires side to run in: left, mid or right\n"
    exit 1
  fi
  ip netns exec "ns_$2" bash
fi
}

main "$@"; exit
