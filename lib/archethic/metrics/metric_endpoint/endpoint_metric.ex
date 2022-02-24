defmodule ArchEthic.Metrics.MetricEndpoint do
  @type ip_as_string() :: String.t()
  @type conn_ref() :: any()
  @type response() :: any()

  @callback retrieve_node_ip_address() :: [String.t()]

  @callback establish_connection(ip_as_string()) :: response() | []

  @callback contact_endpoint(conn_ref()) :: response() | []
end
