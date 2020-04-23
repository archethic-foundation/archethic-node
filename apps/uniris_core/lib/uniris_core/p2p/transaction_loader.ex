defmodule UnirisCore.P2P.TransactionLoader do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.Crypto
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Storage
  alias UnirisCore.PubSub

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    Enum.each(Storage.node_transactions(), &load_transaction/1)

    PubSub.register_to_new_transaction()

    {:ok, []}
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp load_transaction(%Transaction{
         type: :node,
         data: %TransactionData{content: content},
         previous_public_key: previous_public_key
       }) do
    {ip, port} = extract_node_from_content(content)

    previous_address = Crypto.hash(previous_public_key)

    with {:ok, %Transaction{previous_public_key: last_public_key}} <-
           Storage.get_transaction(previous_address),
         {:ok, %Node{first_public_key: first_public_key}} <- P2P.node_info(last_public_key) do
      Node.update_basics(first_public_key, previous_public_key, ip, port)
    else
      _ ->
        P2P.add_node(%Node{
          ip: ip,
          port: port,
          first_public_key: previous_public_key,
          last_public_key: previous_public_key
        })
    end
  end

  defp load_transaction(_), do: :ok

  defp extract_node_from_content(content) do
    [ip_match, port_match] =
      Regex.scan(~r/(?<=ip:|port:|first_public_key:|last_public_key:).*/, content)

    {:ok, ip} =
      ip_match
      |> List.first()
      |> String.trim()
      |> String.to_charlist()
      |> :inet.parse_address()

    port =
      port_match
      |> List.first()
      |> String.trim()
      |> String.to_integer()

    {ip, port}
  end
end
