defmodule Uniris.P2P.TransactionLoader do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.PubSub
  alias Uniris.Storage

  alias Uniris.Transaction
  alias Uniris.TransactionData

  alias Uniris.Utils

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(renewal_interval: renewal_interval) do
    PubSub.register_to_new_transaction()

    initial_state = %{renewal_interval: renewal_interval}

    Enum.each(Storage.node_transactions(), &load_transaction/1)

    case Storage.get_last_node_shared_secrets_transaction() do
      {:ok, tx} ->
        load_transaction(tx)
        {:ok, initial_state}

      _ ->
        {:ok, initial_state}
    end

    {:ok, initial_state}
  end

  def handle_info(
        {:new_transaction,
         %Transaction{
           type: :node_shared_secrets,
           timestamp: timestamp,
           data: %TransactionData{
             keys: %{authorized_keys: authorized_keys}
           }
         }},
        state = %{renewal_interval: renewal_interval}
      ) do
    renewal_offset = Utils.time_offset(renewal_interval)

    if Map.has_key?(state, :ref_authorized_scheduler) do
      Process.cancel_timer(state.ref_authorized_scheduler)
    end

    # Schedule the set of authorized nodes at the renewal interval
    ref_authorized_scheduler =
      Process.send_after(
        self(),
        {:authorize_nodes, Map.keys(authorized_keys), timestamp},
        renewal_offset * 1000
      )

    new_state = Map.put(state, :ref_authorized_scheduler, ref_authorized_scheduler)
    {:noreply, new_state}
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info({:authorize_nodes, nodes, date}, state) do
    Logger.info("new authorized nodes #{inspect(nodes)}")

    Enum.each(nodes, &Node.authorize(&1, date))
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp load_transaction(%Transaction{
         type: :node,
         timestamp: timestamp,
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
          last_public_key: previous_public_key,
          enrollment_date: Utils.truncate_datetime(timestamp)
        })
    end
  end

  defp load_transaction(%Transaction{
         type: :node_shared_secrets,
         data: %TransactionData{
           keys: %{
             authorized_keys: authorized_keys
           }
         },
         timestamp: timestamp
       }) do
    Enum.map(Map.keys(authorized_keys), &Node.authorize(&1, timestamp))
  end

  defp load_transaction(_tx), do: :ok

  defp extract_node_from_content(content) do
    [ip_match, port_match] = Regex.scan(~r/(?<=ip:|port:).*/, content)

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
