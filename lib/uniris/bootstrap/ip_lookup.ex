defmodule Uniris.Bootstrap.IPLookup do
  @moduledoc false

  @behaviour Uniris.Bootstrap.IPLookupImpl

  @impl true
  @spec get_ip() :: :inet.ip_address()
  def get_ip do
    impl().get_ip()
  end

  defp impl do
    :uniris
    |> Application.get_env(Uniris.Bootstrap)
    |> Keyword.fetch!(:ip_lookup_provider)
  end
end
