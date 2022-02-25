defmodule ArchEthic.Metrics.Services.MetricsEndpointBehaviour do
  @moduledoc false

  @type ip_as_string() :: String.t()

  @type conn_ref() :: [] | Mint.t() | any()

  @callback establish_connection(ip_as_string()) :: [] | conn_ref

  @callback contact_endpoint(conn_ref) :: [] | Mint.response()

  @callback request_and_wait_for_response(conn_ref) :: [] | Mint.response()
end
