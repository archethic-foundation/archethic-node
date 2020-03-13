defmodule UnirisSync.TransactionSubscriber do
  use GenServer

  alias UnirisChain.Transaction
  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    UnirisSync.subscribe_new_transaction()
    {:ok, []}
  end

  def handle_info({:new_transaction, %Transaction{type: :node, data: %{content: content}}}, state) do
    node = extract_node_from_content(content)
    :ok = P2P.add_node(node)
    :ok = P2P.connect_node(node)
    Logger.info("New node registered")
    {:noreply, state}
  end

  def handle_info({:new_transaction, %Transaction{}}, state) do
    {:noreply, state}
  end

  defp extract_node_from_content(content) do
    [ip_match, port_match, first_public_key_match, last_public_key_match] =
      Regex.scan(~r/(?<=ip|port|first_public_key|last_public_key).*/, content)

    {:ok, ip} =
      ip_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> String.to_charlist()
      |> :inet.parse_address()

    port =
      port_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> String.to_integer()

    first_public_key =
      first_public_key_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> Base.decode16!()

    last_public_key =
      last_public_key_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> Base.decode16!()

    %Node{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: last_public_key
    }
  end
end
