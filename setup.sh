#!/usr/bin/env bash
set -xu

# A good ressource on Linux Network Namespaces :
# https://blog.scottlowe.org/2013/09/04/introducing-linux-network-namespaces/

main () {
if [[ $# -lt 1 ]]; then 
  printf "Error: setup.sh requires one argument (up, down, or run)\n"
  exit 1
fi

if [[ $1 == "up" ]]; then
  # Crée les trois networks namespace
  for SIDE in "left" "mid" "right"; do
    ip netns add ns_$SIDE
  done;
  for SIDE in "left" "right"; do
    # Crée les paires de virtual ethernets
    ip link add veth_${SIDE}_self type veth peer name veth_${SIDE}_mid
    # Assigne les virtual ethernets aux namespace
    ip link set dev veth_${SIDE}_self netns ns_$SIDE
    ip link set dev veth_${SIDE}_mid netns ns_mid

    # Activer les interfaces virtuelles veth
    # et activer le forwarding ipv4 et ipv6
    # pour left et right
    ip netns exec ns_$SIDE sh -c \
      "ip link set dev veth_${SIDE}_self up &&
      sysctl -w net.ipv6.conf.all.forwarding=1 &&
      sysctl -w net.ipv4.ip_forward=1"
  done

  # Activer les interfaces virtuelles veth
  # et activer le forwarding ipv4 et ipv6
  # pour mid
  ip netns exec ns_mid sh -c \
   "ip link set dev veth_left_mid up &&
    ip link set dev veth_right_mid up &&
    sysctl -w net.ipv6.conf.all.forwarding=1 &&
    sysctl -w net.ipv4.ip_forward=1"

elif [[ $1 == "down" ]]; then
  for SIDE in "left" "right"; do
    ip link delete dev veth_${SIDE}_self
  done;
  for SIDE in "left" "mid" "right"; do
    ip netns delete ns_$SIDE
  done
elif [[ $1 == "run" ]]; then
  if  [[ "$2" == "mid" ]]; then
    ip netns exec "ns_mid" "./bird-2.0.7/bird" -d -s "bird_mid.ctl" -c "bird_mid.conf";
  elif [[ "$2" == "left" || "$2" == "right" ]]; then
    ip netns exec "ns_$2" "./mbird/bird" -d -s "bird_$2.ctl" -c "bird_$2.conf";
  fi
elif [[ $1 == "bash" ]]; then
  if [[ $# -lt 2 ]]; then 
    printf "\`bash\` requires side to run in: left, mid or right\n"
    exit 1
  fi
  ip netns exec "ns_$2" bash
elif [[ $1 == "tmux" ]]; then
  T="ospf"
  tmux new-window -n "$T" bash -c "sudo ip netns exec ns_left bash; read" &&
  tmux split-window -d -t "$T" bash -c "sudo ip netns exec ns_mid bash; read" &&
  tmux split-window -d -t "$T" bash -c "sudo ip netns exec ns_right bash; read" &&
  tmux select-layout even-horizontal
fi
}


TMUX_RUN () {
  if tmux has -t "$1"; then 
    tmux split-window -d -t "$1" bash -c "$2;read"
  else
    tmux new-window -n "$1" bash -c "$2;read"
  fi 
}
main "$@"; exit
