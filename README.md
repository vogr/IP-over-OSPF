# IP over OSPF

The *Open Shortest Path First* routing protocol (OSPF) is widely used on large networks as a way to automatically configure IP routes between machines on this network. To do so, clients build a link-state database (LSDB) containing information relative to all the other hosts participating to the OSPF protocol on the network. Even though this database is designed to contain link-state data, it turns out that the OSPFv3 specification makes it possible for a client to store arbitrary data in it, and synchronize this database with all the other OSPF hosts on the network.

The aim of this project is to use this shared database to exchange IP packets, in essence allowing IP communications using OSPF as the Layer 2 protocol. We therefore defined a new type of entry that could be stored in the LSDB (called *Ethernet LSAs*), which we use to encapsulate Ethernet frames. Note that only the sender and the receiver need to implement this extension ; other routers participating to the OSPF protocol on the autonomous system only need to conform to [RFC 5340](https://tools.ietf.org/html/rfc5340).

In order to implement a proof-of-concept of this extension, we modified the [BIRD Internet Routing Daemon](https://gitlab.labs.nic.cz/labs/bird) (v2.0.7) so that, in addition to being a standard OSPFv3 router, it would:

- Read Ethernet frames from the TAP interface `tap0`, encapsulate these packets in Ethernet LSAs, and add these LSAs to the LSDB.
- React to new Ethernet LSAs in the LSDB by reading its payload, thus obtaining an Ethernet frame, and forwarding the incoming Ethernet frame to the TAP device.

## Compilation

The modified Bird router implementing this extension is available in the directory `mbird/`. Compilation instructions are given in `mbird/INSTALL`.
