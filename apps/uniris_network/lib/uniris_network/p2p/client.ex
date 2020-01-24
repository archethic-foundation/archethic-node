defmodule UnirisNetwork.P2P.Client do
  @moduledoc false

  @behaviour UnirisNetwork.P2P.Client.Impl

  alias UnirisNetwork.Node

  @impl true
  @spec send(Node.t(), binary()) :: {:ok, term, Node.t()} | {:error, :network_issue}
  def send(node = %Node{}, request) when is_binary(request) do
    impl().send(node, request)
  end

  defp impl, do: Application.get_env(:uniris_network, :client, UnirisNetwork.P2P.Client.TCPImpl)
end
