defmodule UnirisSync.Bootstrap.IPLookup do
  @moduledoc false

  @behaviour __MODULE__.Impl

  @impl true
  @spec get_ip() :: :inet.ip_address()
  def get_ip() do
    impl().get_ip()
  end

  defp impl() do
    Application.get_env(:uniris_sync, :ip_provider, __MODULE__.IPFYImpl)
  end

end
