defmodule UnirisNetwork.P2P.SupervisedConnection do
  @moduledoc false

  @behaviour __MODULE__.Impl

  @impl true
  def start_link(public_key, ip, port) do
    impl().start_link(public_key, ip, port)
  end

  @impl true
  def send_message(pid, msg) do
    impl().send_message(pid, msg)
  end

  defp impl(), do: Application.get_env(:uniris_network, :supervised_connection_impl, __MODULE__.TCPImpl)
end
