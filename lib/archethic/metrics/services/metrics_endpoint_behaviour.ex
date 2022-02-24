defmodule ArchEthic.Metrics.Services.MetricsEndpointBehaviour do
  @type ip_as_string() :: String.t()
  @type response() :: any()


  @callback establish_connection(ip_as_string()) :: response() | []
end
