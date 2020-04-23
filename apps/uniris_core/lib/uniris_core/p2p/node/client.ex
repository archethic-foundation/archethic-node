defmodule UnirisCore.P2P.NodeClient do
  @moduledoc false

  @behaviour UnirisCore.P2P.NodeClientImpl

  @impl true
  @spec start_link(opts :: [ip: :inet.ip_address(), port: :inet.port_number(), parent_pid: pid()]) ::
          {:ok, pid()}
  def start_link(opts) do
    impl().start_link(opts)
  end

  @impl true
  @spec send_message(client :: pid(), message :: term()) ::
          response :: term()
  def send_message(pid, message) do
    impl().send_message(pid, message)
  end

  defp impl() do
    :uniris_core
    |> Application.get_env(UnirisCore.P2P)
    |> Keyword.fetch!(:node_client)
  end
end
