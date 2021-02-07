-define(NAT_TRIES, 3).
-define(NAT_INITIAL_MS, 250).

-define(RECOMMENDED_MAPPING_LIFETIME_SECONDS, 7200).

-record(nat_upnp, {service_url, ip}).
