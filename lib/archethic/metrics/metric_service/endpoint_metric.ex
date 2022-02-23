defmodule ArchEthic.Metrics.EndpointMetric do
  @type ip_as_string :: String.t()

  @callback fetch_raw_metrics([ip_as_string]) :: String.t()
end
