defmodule Uniris.P2P do
  @moduledoc """
  High level P2P functions
  """
  alias Uniris.Crypto

  alias __MODULE__.Client
  alias __MODULE__.Node

  alias Uniris.Storage.Memory.NetworkLedger

  @doc """
  Returns information about the running node
  """
  @spec node_info() :: {:ok, Node.t()} | {:error, :not_found}
  def node_info do
    NetworkLedger.get_node_info(Crypto.node_public_key(0))
  end

  @doc """
  Send a P2P message to a node
  """
  @spec send_message(Uniris.Crypto.key() | Node.t(), Message.t()) :: Message.t()
  def send_message(public_key, message) when is_binary(public_key) do
    {:ok, node} = NetworkLedger.get_node_info(public_key)
    do_send_message(node, message)
  end

  @spec send_message(Node.t(), Message.t()) :: Message.t()
  def send_message(node = %Node{}, message) do
    do_send_message(node, message)
  end

  defp do_send_message(%Node{ip: ip, port: port, first_public_key: first_public_key}, message) do
    case Client.send_message(ip, port, message) do
      {:ok, data} ->
        NetworkLedger.increase_node_availability(first_public_key)
        data

      {:error, :network_issue} ->
        :ok = NetworkLedger.decrease_node_availability(first_public_key)
        raise "Messaging error with #{:inet.ntoa(ip)}:#{port}"
    end
  end

  @doc """
  Get the nearest nodes from a specified node and a list of nodes to compare with

  ## Examples

     iex> list_nodes = [%{network_patch: "AA0"}, %{network_patch: "F50"}, %{network_patch: "3A2"}]
     iex> Uniris.P2P.nearest_nodes(list_nodes, "12F")
     [
       %{network_patch: "3A2"},
       %{network_patch: "AA0"},
       %{network_patch: "F50"}
     ]

     iex> list_nodes = [%{network_patch: "AA0"}, %{network_patch: "F50"}, %{network_patch: "3A2"}]
     iex> Uniris.P2P.nearest_nodes(list_nodes, "C3A")
     [
       %{network_patch: "AA0"},
       %{network_patch: "F50"},
       %{network_patch: "3A2"}
     ]
  """
  @spec nearest_nodes(node_list :: nonempty_list(Node.t()), network_patch :: binary()) ::
          list(Node.t())
  def nearest_nodes(storage_nodes, network_patch)
      when is_list(storage_nodes) and is_binary(network_patch) do
    from_node_position = network_patch |> String.to_charlist() |> List.to_integer(16)

    Enum.sort_by(storage_nodes, fn storage_node ->
      storage_node_position =
        storage_node.network_patch |> String.to_charlist() |> List.to_integer(16)

      abs(storage_node_position - from_node_position)
    end)
  end
end
