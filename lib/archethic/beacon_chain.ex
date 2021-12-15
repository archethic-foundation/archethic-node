defmodule ArchEthic.BeaconChain do
  @moduledoc """
  Manage the beacon chain by providing functions to add to the subsets information and
  to retrieve the beacon storage nodes involved.
  """

  alias ArchEthic.Election

  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.Slot.Validation, as: SlotValidation

  alias ArchEthic.BeaconChain.SlotTimer
  alias ArchEthic.BeaconChain.Subset
  alias ArchEthic.BeaconChain.Subset.P2PSampling
  alias ArchEthic.BeaconChain.Summary
  alias ArchEthic.BeaconChain.SummaryTimer

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.P2P.Message.RegisterBeaconUpdates

  alias ArchEthic.PubSub

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.Utils

  require Logger

  @doc """
  Initialize the beacon subsets (from 0 to 255 for a byte capacity)
  """
  @spec init_subsets() :: :ok
  def init_subsets do
    subsets = Enum.map(0..255, &:binary.encode_unsigned(&1))
    :persistent_term.put(:beacon_subsets, subsets)
  end

  @doc """
  List of all transaction subsets (255 subsets for a byte capacity)

  ## Examples

      BeaconChain.list_subsets()
      [ <<0>>, <<1>>,<<2>>, <<3>> ... <<253>>, <<254>>, <255>>]
  """
  @spec list_subsets() :: list(binary())
  def list_subsets do
    :persistent_term.get(:beacon_subsets)
  end

  @doc """
  Retrieve the beacon summaries storage nodes from a last synchronization date
  """
  @spec get_summary_pools(list(DateTime.t()), list(Node.t())) :: Enumerable.t()
  def get_summary_pools(
        summary_times,
        node_list \\ P2P.authorized_nodes()
      ) do
    subsets = list_subsets()

    window = Utils.flow_window_from_dates(summary_times, &elem(&1, 0))

    summary_times
    |> Flow.from_enumerable()
    |> Flow.flat_map(fn time ->
      Enum.map(subsets, fn subset -> {DateTime.truncate(time, :second), subset} end)
    end)
    |> Flow.partition(window: window, key: {:elem, 1})
    |> Flow.reduce(fn -> [] end, fn {time, subset}, acc ->
      [{time, subset, get_beacon_chain_pool(time, subset, node_list)} | acc]
    end)
    |> Flow.emit(:state)
    |> Stream.flat_map(& &1)
  end

  defp get_beacon_chain_pool(time, subset, node_list) do
    filter_nodes = Enum.filter(node_list, &(DateTime.compare(&1.authorization_date, time) == :lt))
    Election.beacon_storage_nodes(subset, time, filter_nodes)
  end

  @doc """
  Get the next beacon summary time
  """
  @spec next_summary_date(DateTime.t()) :: DateTime.t()
  defdelegate next_summary_date(date), to: SummaryTimer, as: :next_summary

  @doc """
  Get the next beacon slot time from a given date
  """
  @spec next_slot(last_sync_date :: DateTime.t()) :: DateTime.t()
  defdelegate next_slot(last_sync_date), to: SlotTimer

  @doc """
  Retrieve the beacon slots storage nodes from a last synchronization date
  """
  @spec get_slot_pools(list(DateTime.t()), list(Node.t())) :: Enumerable.t()
  def get_slot_pools(slot_times, node_list \\ P2P.authorized_nodes()) do
    subsets = list_subsets()

    window = Utils.flow_window_from_dates(slot_times, &elem(&1, 0))

    slot_times
    |> Flow.from_enumerable()
    |> Flow.flat_map(fn time ->
      Enum.map(subsets, fn subset -> {DateTime.truncate(time, :second), subset} end)
    end)
    |> Flow.partition(window: window, key: {:elem, 1})
    |> Flow.reduce(fn -> [] end, fn {time, subset}, acc ->
      [{time, subset, get_beacon_chain_pool(time, subset, node_list)} | acc]
    end)
    |> Flow.emit(:state)
    |> Stream.flat_map(& &1)
  end

  @doc """
  Extract the beacon subset from an address

  ## Examples

      iex> BeaconChain.subset_from_address(<<0, 44, 242, 77, 186, 95, 176, 163,
      ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
      ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
      <<44>>
  """
  @spec subset_from_address(binary()) :: binary()
  def subset_from_address(address) do
    :binary.part(address, 1, 1)
  end

  @doc """
  Add a transaction to the beacon chain
  """
  @spec add_transaction_summary(Transaction.t()) :: :ok
  def add_transaction_summary(tx = %Transaction{address: address}) do
    address
    |> subset_from_address()
    |> Subset.add_transaction_summary(TransactionSummary.from_transaction(tx))

    PubSub.notify_new_transaction(address)
  end

  @doc """
  Add a node entry into the beacon chain subset
  """
  @spec add_end_of_node_sync(Crypto.key(), DateTime.t()) :: :ok
  def add_end_of_node_sync(
        node_public_key = <<_::8, _::8, subset::binary-size(1), _::binary>>,
        timestamp = %DateTime{}
      )
      when is_binary(node_public_key) do
    Subset.add_end_of_node_sync(subset, %EndOfNodeSync{
      public_key: node_public_key,
      timestamp: timestamp
    })
  end

  @doc """
  Get the transaction address for a beacon chain daily summary based from a subset and date
  """
  @spec summary_transaction_address(binary(), DateTime.t()) :: binary()
  def summary_transaction_address(subset, date = %DateTime{}) when is_binary(subset) do
    {pub, _} =
      Crypto.derive_keypair(
        Crypto.storage_nonce(),
        Crypto.hash([subset, <<DateTime.to_unix(date)::32>>])
      )

    Crypto.hash(pub)
  end

  @doc """
  Return the previous summary time
  """
  @spec previous_summary_time(DateTime.t()) :: DateTime.t()
  defdelegate previous_summary_time(date_from), to: SummaryTimer, as: :previous_summary

  @doc """
  Load the transaction in the beacon chain context
  """
  @spec load_transaction(Transaction.t()) :: :ok | :error
  def load_transaction(
        tx = %Transaction{
          address: address,
          type: :beacon,
          data: %TransactionData{content: content}
        }
      ) do
    with false <- TransactionChain.transaction_exists?(address),
         {%Slot{subset: subset, slot_time: slot_time} = slot, _} <- Slot.deserialize(content),
         :ok <- validate_slot(tx, slot) do
      summary_address = summary_transaction_address(subset, next_summary_date(slot_time))
      TransactionChain.write_transaction(tx, summary_address)
    else
      true ->
        :ok

      {:error, _} = e ->
        Logger.error("Invalid beacon slot #{inspect(e)}")
        :error
    end
  end

  def load_transaction(_), do: :ok

  defp validate_slot(
         %Transaction{address: address},
         slot = %Slot{subset: subset, slot_time: slot_time}
       ) do
    cond do
      address != Crypto.derive_beacon_chain_address(subset, slot_time) ->
        {:error, :invalid_address}

      !SlotValidation.valid_transaction_summaries?(slot) ->
        {:error, :invalid_transaction_summaries}

      !SlotValidation.valid_end_of_node_sync?(slot) ->
        {:error, :invalid_end_of_node_sync}

      true ->
        :ok
    end
  end

  @doc """
  List the nodes for the subset to sample the P2P availability
  """
  @spec list_p2p_sampling_nodes(binary()) :: list(Node.t())
  defdelegate list_p2p_sampling_nodes(subset), to: P2PSampling, as: :list_nodes_to_sample

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(SummaryTimer)
    |> SummaryTimer.config_change()

    changed_conf
    |> Keyword.get(SlotTimer)
    |> SlotTimer.config_change()
  end

  @doc """
  Get a beacon chain summary representation by loading from the database the transaction
  """
  @spec get_summary(binary()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_summary(address) when is_binary(address) do
    case TransactionChain.get_transaction(address, data: [:content]) do
      {:ok, %Transaction{data: %TransactionData{content: content}}} ->
        {summary, _} = Summary.deserialize(content)
        {:ok, summary}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Return the previous summary datetimes from a given date
  """
  @spec previous_summary_dates(DateTime.t()) :: Enumerable.t()
  defdelegate previous_summary_dates(date), to: SummaryTimer, as: :previous_summaries

  @doc """
  Return a list of beacon summaries from a list of transaction addresses
  """
  @spec get_beacon_summaries(list(binary)) :: Enumerable.t() | list(Summary.t())
  def get_beacon_summaries(addresses) do
    addresses
    |> Stream.map(&get_summary/1)
    |> Stream.reject(&match?({:error, :not_found}, &1))
    |> Stream.map(fn {:ok, summary} -> summary end)
  end

  @doc """
   subscribe for beacon updates i.e add to subscribed list takes for given subset and node_public_key
  """
  def subscribe_for_beacon_updates(subset, node_public_key) do
    # check node list and subscribe to subset if exist
    if Utils.key_in_node_list?(P2P.authorized_nodes(), node_public_key) do
      Logger.debug(
        "Added Node Public key=#{Base.encode16(node_public_key)} as subscriber for subset=#{Base.encode16(subset)} in BeaconChain"
      )

      Subset.subscribe_for_beacon_updates(subset, node_public_key)
    end
  end

  @doc """
   Register for beacon updates i.e send a P2P message for beacon updates
  """
  def register_to_beacon_pool_updates(date = %DateTime{} \\ next_slot(DateTime.utc_now())) do
    Enum.map(list_subsets(), fn subset ->
      nodes = Election.beacon_storage_nodes(subset, date, P2P.authorized_nodes())

      P2P.broadcast_message(nodes, %RegisterBeaconUpdates{
        node_public_key: Crypto.first_node_public_key(),
        subset: subset
      })
    end)
  end
end
