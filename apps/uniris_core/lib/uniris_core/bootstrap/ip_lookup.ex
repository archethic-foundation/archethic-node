defmodule UnirisCore.Bootstrap.IPLookup do
  @moduledoc false

  @behaviour UnirisCore.Bootstrap.IPLookupImpl

  @impl true
  @spec get_ip() :: :inet.ip_address()
  def get_ip do
    impl().get_ip()
  end

  defp impl do
    :uniris_core
    |> Application.get_env(UnirisCore.Bootstrap)
    |> Keyword.fetch!(:ip_lookup_provider)
  end
end
