# IP over OSPF

## Summary

The *Open Shortest Path First* routing protocol (OSPF) is widely used on large networks as a way to automatically configure IP routes between machines on this network. To do so, clients build a link-state database (LSDB) containing information relative to all the other hosts participating to the OSPF protocol on the network. Even though this database is designed to contain link-state data, it turns out that the OSPFv3 specification makes it possible for a client to store arbitrary data in it, and synchronize this database with all the other OSPF hosts on the network.

The aim of this project is to use this shared database to exchange IP packets, in essence allowing IP communications using OSPF as the Layer 2 protocol. We therefore defined a new type of entry that could be stored in the LSDB (called *Ethernet LSAs*), which we use to encapsulate Ethernet frames. Note that only the sender and the receiver need to implement this extension ; other routers participating to the OSPF protocol on the autonomous system only need to conform to [RFC 5340](https://tools.ietf.org/html/rfc5340).

In order to implement a proof-of-concept of this extension, we modified the [BIRD Internet Routing Daemon](https://gitlab.labs.nic.cz/labs/bird) (v2.0.7) so that, in addition to being a standard OSPFv3 router, it would:

- Read Ethernet frames from the TAP interface `tap0`, encapsulate these packets in Ethernet LSAs, and add these LSAs to the LSDB.
- React to new Ethernet LSAs in the LSDB by reading its payload, thus obtaining an Ethernet frame, and forwarding the incoming Ethernet frame to the TAP device.

### Compilation

The modified Bird router implementing this extension is available in the directory `mbird/`. Compilation instructions are given in `mbird/INSTALL`.


## Introduction


The *Open Shortest Path First* routing protocol is widely used on large
networks as a way to automatically configure IP routes between machines
on this network. This document describes an extension to the OSPF
protocol that makes it possible for multiple clients to exchange IP
packets (in Ethernet frames) using only the OSPF protocol (i.e. without
using the IP routes established by the underlying OSPF instance).
Multiple versions of the OSPF protocol have been specified over time ;
this document will only refer to the version defined in ["RFC5240 --
OSPF for IPv6"](https://tools.ietf.org/html/rfc5340), referred to as
OSPFv3.

In the OSPF protocol, clients build a link-state database (LSDB)
containing information relative to all the other hosts participating to
the OSPF protocol on the network. Entries in the LSDB are called
Link-State Advertisements (LSAs). Hosts add data relative to their
neighbors in the database, and synchronize this new data with all the
other OSPF hosts. Even though this database is designed to contain
link-state data, the OSPFv3 protocol makes it possible for a client to
store arbitrary data in it, and synchronize this database with all the
other OSPF hosts on the network.

To do so, our extension defines a new type of LSA : the Ethernet LSA.
Clients willing to exchange Ethernet frames over OSPF must be
participating to the same OSPF protocol instance (i.e. their LSDBs are
kept in sync by the OSPF protocol). The sender will build an Ethernet
LSA entry with the Ethernet frame as a payload, and add this LSA to the
LSDB. The LSDB will be synchronized with all OSPF hosts (even those who
have no knowledge of this extension and do not recognize the Ethernet
LSA type). The receiver will notice the Ethernet LSA in the LSDB and
will read the payload, thus obtaining the Ethernet frame.

#### 

In order to implement a proof-of-concept of this extension, we modified
the [*BIRD Internet Routing
Daemon*](https://gitlab.labs.nic.cz/labs/bird) (v2.0.7) so that, in
addition to being a standard OSPFv3 router, it would:

-   read Ethernet frames from a TAP interface, encapsulate these packets
    in Ethernet LSAs, and add these LSAs to the LSDB.

-   react to new Ethernet LSAs in the LSDB by reading its payload, thus
    obtaining an Ethernet frame, and forwarding the incoming Ethernet
    frame to the TAP device.

will describe the technical details of the modifications we made to the
*BIRD Internet Routing Daemon*. will specify the protocol used to
exchange Ethernet frames over OSPFv3.

## Implementation


### Creation of a new type of LSA : 


LSAs stored in the LSDB are all defined by their type (a two-octet long
integer field). Only 9 types are defined in the OSPFv3 spec. A new LSA
type should not be chosen at random among the remaining values: the
three higher bits of the LSA type determine how the LSAs will be handled
by routers which have no knowledge of this type (see
[RFC5340\#A.4.2.1](https://tools.ietf.org/html/rfc5340#appendix-A.4.2.1)).
We chose the type (in hexadecimal), which has the following binary
representation:

    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |U |S2|S1|           LSA Function Code          |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |1 | 1| 0| 0  0  0  0  0  0  0  0  0  1  1  1  1|
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+

This choice ensures that the LSA will be stored and flooded by all
routers on the autonomous system.

We define this new type in and create a new structure:

``` {.C}
#define LSA_T_ETH   0xC00F

struct ospf_lsa_eth
{
  u32 data_length;
  u8 data[2048];
};
```

We wrote two new functions in order to generate Ethernet LSA in :

``` {.C}
void prepare_eth_lsa_body(struct ospf_proto *p,
                     u8 *eth_frame_buffer, size_t frame_length);
                     
void ospf_originate_eth_lsa(struct ospf_proto *p,
                       u8 *eth_frame_buffer, size_t frame_length);
```

The second function takes as parameters a variable representing the OSPF
instance (), and a buffer (with its length) containing an Ethernet frame
to send over OSPF (). This second function uses the first one to
allocate memory and create the body of LSA, using the structure defined
in . It then fills its header (with the type and an ID) and adds it to
the LSDB. The LSDB can only contain one LSA for each tuple (type, ID,
OSPF router ID) ; to prevent collisions we increment the ID every time
we add a new LSA. The ID is reset to 0 when it reaches $2^{20}$ to limit
memory use.

The function is called in file, in the function. This is where BIRD
deals with incoming data on all interfaces.We added the TAP device to
the list of interfaced to , and defined a branch to deal with incoming
Ethernet frames on the TAP device.

TAP device
----------

### Helper functions and variables

In :

``` {.C}
int get_tapfd(void);
int tap_open(char *devname);
```

The function initialize the tap device and set the MTU to 2048 so that
incoming packets fit in the Ethernet LSA.

allows other part of the code to request the file descriptor of the TAP
device. It is used in the function dealing with incoming LSAs from other
hosts on the network ; when a new Ethernet LSA arrives, its payload (the
Ethernet frame) is written to the TAP device.

#### 

In :

``` {.C}
struct ospf_proto *global_ospf_proto;
struct ospf_proto *get_global_ospf_proto(void);
```

The function takes a argument. This structure is created in and
describes the full state of the OSPF instance (including LSDB and
neighbors). We created a variable named and a function to get it, in
order to use it in the function from the , so that we could deal with
incoming Ethernet frames on the TAP device by writing Ethernet LSAs in
the LSDB.

#### Reading Ethernet frames from TAP interface and creating Ethernet LSAs

In the file, in the main loop (), we first initialize the TAP device
using the function. Then, we add the file descriptor for this device to
the list of files descriptors to poll. The takes care of every other
file descriptor and we treat TAP separately.

Now, we deal with incoming packets on TAP interface. We read the packet
from the TAP interface and create an Ethernet LSA (with the received
packet from TAP in the payload) using the function we created.

#### Writing Ethernet frames from Ethernet LSA body on TAP

In :

``` {.C}
void send_lsa_eth_body_to_tap(void* body) 
struct top_hash_entry *ospf_install_lsa(
    struct ospf_proto *p, struct ospf_lsa_header *lsa,
    u32 type, u32 domain, void *body)
```

We create the function , which write the body argument on tap. We use
the function to get the TAP file descriptor created in the file.

The function is called when LSA are received in a LS Update packet. We
deal with incoming Ethernet LSAs in this function: if the type of the
new LSA is , we call on the payload.

### Potential improvements


In , the function can't support Ethernet frames larger than 2048 bytes.
It could be an improvement to find a way to support larger Ethernet
frame sizes or to accept all possible sizes. Currently, we set the MTU
to limit the size of Ethernet frames read on the TAP device.

In the same function, we could find a cleaner solution than using an
increment and a modulo to give IDs to the LSAs. Currently, to limit
memory use, we reset the ID to 0 when it reaches $2^{20}$. It is enough
for our utilisation of the program, even though it is quite arbitrary.

## Specification


### Introduction


This section specifies the extension to OSPFv3 used in the previous
implementation. Any client conforming to this specification should be
able to exchange Ethernet frames over OSPFv3 with other conformant
clients.

Note that only clients willing to send or receive Ethernet frames with
this protocol need to implement the extension ; other routers
participating to the OSPF protocol on the autonomous system only need to
conform to RFC 5340.

### The Ethernet LSA format


We define a new type of LSA, called Ethernet LSA, to encapsulate
Ethernet frames. This LSA uses type `c00f` (in hexadecimal). Any
Ethernet LSA must also be a valid LSA, as described in
[RFC5340\#4.4.1](https://tools.ietf.org/html/rfc5340#section-4.4.1),
i.e. it must have the standard 20-octet-long header (see Figure
[\[fig:format\]](#fig:format){reference-type="ref"
reference="fig:format"}).

    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |           LS Age              |1|1|0|            15           |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                       Link State ID                           |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                    Advertising Router                         |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                    LS Sequence Number                         |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |        LS Checksum            |             Length            |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                        Ethernet frame                         |
    |                              ...                              |
    |                              ...                              |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

All integer fields should be in network-byte-order.

#### Writing an Ethernet LSA

When building a new Ethernet LSA to encapsulate an Ethernet frame:

-   The Age field should be set to 0.

-   The Type field should be the two-octet-long integer `c00f`
    (hexadecimal).

-   The Link State ID should be a four octets integer.

-   The Advertising Router should be the ID of the sender.

-   The LS Sequence Number should be set to 0.

-   The LS Checksum should be the Fletcher Checksum of the LSA, as
    detailed in RFC5340.

-   The Length should be the full length of the LSA in octets.

#### Reading an Ethernet LSA

When reading an Ethernet LSA, the receiver:

-   Should check that the LSA is valid, as described in RFC5340.

-   May interpret the payload as an Ethernet frame.

### IP-over-OSPF protocol


A client willing to participate in the IP-over-OSPF protocol:

-   Should be a valid OSPFv3 router, and be in the same network of
    OSPFv3 routers as the host it wishes to exchange Ethernet frames
    with.

-   Should encapsulate the Ethernet frame it wishes to send in an
    Ethernet LSA, then add this LSA to its LSDB. The client can give any
    Link State ID to this LSA, but should avoid using an ID used on an
    Ethernet LSA it sent in the past and which has not been read by its
    recipient yet.

-   Should interpret the payload of any Ethernet LSA arriving in its
    LSDB as an Ethernet frame, except if it created this particular LSA.
