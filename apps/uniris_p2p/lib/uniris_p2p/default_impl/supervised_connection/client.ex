defmodule UnirisP2P.DefaultImpl.SupervisedConnection.Client do
  @moduledoc false

  @behaviour __MODULE__.Impl

  @impl true
  @spec start_link(
          ip :: :inet.ip_address(),
          port :: :inet.port_number(),
          parent :: pid()
        ) ::
          {:ok, pid()}
  def start_link(ip, port, parent) do
    impl().start_link(ip, port, parent)
  end

  @impl true
  @spec send_message(client :: pid(), message: term()) :: term()
  def send_message(pid, message) do
    impl().send_message(pid, message)
  end

  defp impl() do
    Application.get_env(:uniris_p2p, :p2p_client, __MODULE__.TCPImpl)
  end
end
