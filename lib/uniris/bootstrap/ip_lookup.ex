defmodule Uniris.Bootstrap.IPLookup do
  @moduledoc false

  alias Uniris.Bootstrap.IPLookupImpl

  @behaviour IPLookupImpl

  @impl IPLookupImpl
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
