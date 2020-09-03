defmodule Uniris.BeaconSubset do
  @moduledoc """
  Represents a beacon subset running inside a process
  waiting to receive transactions to register in a beacon block
  through the several slots (time based)
  """

  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.NodeInfo
  alias Uniris.BeaconSlot.TransactionInfo

  alias Uniris.BeaconSubsetRegistry

  alias Uniris.PubSub

  alias Uniris.Transaction
  alias Uniris.TransactionData

  use GenServer

  require Logger

  def start_link(opts) do
    subset = Keyword.get(opts, :subset)
    GenServer.start_link(__MODULE__, [subset], name: via_tuple(subset))
  end

  def init([subset]) do
    {:ok,
     %{
       subset: subset,
       current_slot: %BeaconSlot{},
       slots: %{}
     }}
  end

  def handle_call(
        {:add_transaction_info, tx_info = %TransactionInfo{address: address}},
        _from,
        state = %{current_slot: %BeaconSlot{transactions: transactions}}
      ) do
    if Enum.any?(transactions, &(&1.address == address)) do
      {:reply, :ok, state}
    else
      Logger.info(
        "Transaction #{Base.encode16(tx_info.address)} added to the beacon chain (subset #{
          Base.encode16(state.subset)
        })"
      )

      PubSub.notify_new_transaction(address)

      {:reply, :ok,
       Map.update!(state, :current_slot, &BeaconSlot.add_transaction_info(&1, tx_info))}
    end
  end

  def handle_call({:add_node_info, node_info = %NodeInfo{}}, _from, state) do
    Logger.info(
      "Node #{inspect(node_info)} info added to the beacon chain subset(#{
        Base.encode16(state.subset)
      })"
    )

    {:reply, :ok, Map.update!(state, :current_slot, &BeaconSlot.add_node_info(&1, node_info))}
  end

  def handle_call({:previous_slots, last_sync_date}, _, state = %{slots: slots}) do
    previous_slots =
      slots
      |> Enum.filter(fn {time, _} -> DateTime.compare(time, last_sync_date) == :gt end)
      |> Enum.sort_by(fn {time, _} -> time end)
      |> Enum.map(fn {_, %Transaction{data: %{content: content}}} ->
        content
        |> String.split("\n")
        |> Enum.reduce(%BeaconSlot{}, &do_reduce_slots/2)
      end)

    {:reply, previous_slots, state}
  end

  defp do_reduce_slots(line, slot) do
    case String.split(line, " - ") do
      ["T", type, timestamp, address | movements_addresses] ->
        BeaconSlot.add_transaction_info(slot, %TransactionInfo{
          address: Base.decode16!(address),
          timestamp: timestamp |> String.to_integer() |> DateTime.from_unix!(),
          type: Transaction.parse_type(String.to_integer(type)),
          movements_addresses: Enum.map(movements_addresses, &Base.decode16!/1)
        })

      ["N", public_key, timestamp, "R"] ->
        BeaconSlot.add_node_info(slot, %NodeInfo{
          public_key: Base.decode16!(public_key),
          ready?: true,
          timestamp: timestamp |> String.to_integer() |> DateTime.from_unix!()
        })
    end
  end

  def handle_info(
        {:create_slot, _slot_time},
        state = %{current_slot: %BeaconSlot{transactions: [], nodes: []}}
      ) do
    {:noreply, state}
  end

  def handle_info({:create_slot, slot_time = %DateTime{}}, state = %{current_slot: current_slot}) do
    tx = Transaction.new(:beacon, %TransactionData{content: output_slot(current_slot)})

    new_state =
      state
      |> Map.put(:current_slot, %BeaconSlot{})
      |> put_in([:slots, slot_time], tx)

    Logger.info(
      "Beacon slot created with #{Enum.map(current_slot.transactions, &Base.encode16(&1.address))} at #{
        inspect(slot_time)
      }"
    )

    {:noreply, new_state}
  end

  defp output_slot(%BeaconSlot{transactions: [], nodes: nodes}) do
    output_nodes(nodes)
  end

  defp output_slot(%BeaconSlot{transactions: transactions, nodes: []}) do
    output_transactions(transactions)
  end

  defp output_slot(%BeaconSlot{transactions: transactions, nodes: nodes}) do
    output_transactions(transactions) <> "\n" <> output_nodes(nodes)
  end

  defp output_transactions(transactions) do
    Enum.map(transactions, fn %TransactionInfo{
                                address: address,
                                timestamp: timestamp,
                                type: type,
                                movements_addresses: movements_addresses
                              } ->
      movements_addresses_str =
        movements_addresses
        |> Enum.map(&Base.encode16/1)
        |> Enum.join(" - ")

      "T - #{Transaction.serialize_type(type)} - #{DateTime.to_unix(timestamp)} - #{
        address |> Base.encode16()
      } - #{movements_addresses_str}"
    end)
    |> Enum.join("\n")
  end

  defp output_nodes(nodes) do
    Enum.map(nodes, fn %NodeInfo{public_key: public_key, ready?: ready?, timestamp: timestamp} ->
      infos = []

      infos =
        if ready? do
          infos ++ ["R"]
        end

      "N - #{Base.encode16(public_key)} - #{DateTime.to_unix(timestamp)} - #{
        Enum.join(infos, " - ")
      }"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Add transaction informations to the current block of the given subset
  """
  @spec add_transaction_info(sbuset :: binary(), Transaction.info()) :: :ok
  def add_transaction_info(subset, tx_info = %TransactionInfo{}) when is_binary(subset) do
    GenServer.call(via_tuple(subset), {:add_transaction_info, tx_info})
  end

  @doc """
  Add node informations to the current block of the given subset
  """
  @spec add_node_info(subset :: binary(), NodeInfo.t()) :: :ok
  def add_node_info(subset, node_info = %NodeInfo{}) when is_binary(subset) do
    GenServer.call(via_tuple(subset), {:add_node_info, node_info})
  end

  @doc """
  Get the last informations from a beacon subset slot before the last synchronized date 
  """
  @spec previous_slots(binary(), last_sync_date :: DateTime.t()) :: list(BeaconSlot.t())
  def previous_slots(subset, last_sync_date = %DateTime{}) when is_binary(subset) do
    subset
    |> via_tuple
    |> GenServer.call({:previous_slots, last_sync_date})
  end

  defp via_tuple(subset) do
    {:via, Registry, {BeaconSubsetRegistry, subset}}
  end
end
