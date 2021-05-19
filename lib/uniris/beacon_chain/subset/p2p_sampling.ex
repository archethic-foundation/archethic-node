defmodule Uniris.BeaconChain.Subset.P2PSampling do
  @moduledoc false

  alias Uniris.P2P
  alias Uniris.P2P.Message
  alias Uniris.P2P.Message.Ping
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Node
  alias Uniris.P2P.Transport

  @type p2p_view :: {available? :: boolean(), latency :: non_neg_integer()}

  @doc """
  Provide the list of nodes to sample for the given subset
  """
  @spec list_nodes_to_sample(binary()) :: list(Node.t())
  def list_nodes_to_sample(<<subset::8>>) do
    P2P.available_nodes()
    |> Enum.filter(fn %Node{first_public_key: <<_::8, first_digit::8, _::binary>>} ->
      first_digit == subset
    end)
    |> Enum.sort_by(& &1.first_public_key)
  end

  @doc """
  Get the p2p view for the given nodes while computing the bandwidth from the latency
  """
  @spec get_p2p_views(list(Node.t())) :: list(p2p_view())
  def get_p2p_views(nodes) when is_list(nodes) do
    nodes
    |> Task.async_stream(&do_sample_p2p_view/1)
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  defp do_sample_p2p_view(node = %Node{}) do
    if P2P.has_connection?(node) do
      sample_p2p_view_with_connection(node)
    else
      sample_p2p_view_without_connection(node)
    end
  end

  defp sample_p2p_view_with_connection(node = %Node{}) do
    start_time = System.monotonic_time(:millisecond)

    case P2P.send_message(node, %Ping{}) do
      {:ok, %Ok{}} ->
        end_time = System.monotonic_time(:millisecond)
        latency = end_time - start_time
        {true, trunc(latency)}

      _ ->
        {false, 0}
    end
  end

  defp sample_p2p_view_without_connection(%Node{transport: transport, ip: ip, port: port}) do
    start_time = System.monotonic_time(:millisecond)

    case Transport.connect(transport, ip, port) do
      {:ok, socket} ->
        with :ok <- Transport.send_message(transport, socket, Message.encode(%Ping{})),
             {:ok, %Ok{}} <- Transport.read_from_socket(transport, socket) do
          end_time = System.monotonic_time(:millisecond)
          Transport.close_socket(transport, socket)

          latency = end_time - start_time
          {true, trunc(latency)}
        else
          _ ->
            Transport.close_socket(transport, socket)
            {false, 0}
        end

      _ ->
        {false, 0}
    end
  end
end
