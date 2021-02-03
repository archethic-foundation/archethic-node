-module(nat).

-type nat_upnp() :: any().
-type nat_protocol() :: tcp | udp.

-export_type([nat_upnp/0, nat_protocol/0]).