defmodule ArchEthic.Metrics.Services.MetricsEndpointBehaviour do
  @moduledoc false

  @type ip_as_string() :: String.t()
  @type conn_ref() :: Mint.t() | any()

  @callback get_metrics_from_node(ip_as_string()) :: [] | Mint.response()

  @callback retrieve_node_ip_address :: [ip_as_string()]

  @callback establish_connection_to_node(ip_as_string()) :: [] | Mint.response()

  @callback contact_endpoint_for_data(conn_ref()) :: [] | Mint.response()
end
