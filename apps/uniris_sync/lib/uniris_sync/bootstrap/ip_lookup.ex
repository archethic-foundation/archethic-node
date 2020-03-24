defmodule UnirisSync.Bootstrap.IPLookup do
  @moduledoc false

  @behaviour __MODULE__.Impl

  @impl true
  def get_public_ip() do
    impl().get_public_ip()
  end

  defp impl() do
    Application.get_env(:uniris_sync, :public_ip_provider, __MODULE__.IPFYImpl)
  end

end
