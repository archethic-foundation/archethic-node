defmodule Uniris.BeaconChain do
  @moduledoc """
  Manage the beacon chain by providing functions to add to the subsets information and
  to retrieve the beacon storage nodes involved.
  """

  alias Uniris.Election

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Subset
  alias Uniris.BeaconChain.Summary
  alias Uniris.BeaconChain.SummaryTimer
  alias Uniris.BeaconChain.SummaryValidation

  alias Uniris.Crypto

  alias Uniris.DB

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.PubSub

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction

  require Logger

  @type summary_pools ::
          list({
            subset :: binary(),
            nodes_by_summary_date :: list({DateTime.t(), list(Node.t())})
          })

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
  Retrieve the beacon storage nodes from a last synchronization date

  For each subsets available, the computation will be done to find out the missing synchronization summaries
  """
  @spec get_summary_pools(DateTime.t()) :: list({subset :: binary(), nodes: list(Node.t())})
  def get_summary_pools(
        last_sync_date = %DateTime{},
        node_list \\ P2P.list_nodes(availability: :global)
      ) do
    summary_times = SummaryTimer.previous_summaries(last_sync_date)

    Enum.reduce(list_subsets(), [], fn subset, acc ->
      nodes_by_summary_time =
        Enum.map(summary_times, fn time ->
          {time, Election.beacon_storage_nodes(subset, time, node_list)}
        end)

      [{subset, nodes_by_summary_time} | acc]
    end)
  end

  @doc """
  Get the next beacon slot time from a given date
  """
  @spec next_slot(last_sync_date :: DateTime.t()) :: DateTime.t()
  defdelegate next_slot(last_sync_date), to: SlotTimer

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
  def add_end_of_node_sync(node_public_key, timestamp = %DateTime{})
      when is_binary(node_public_key) do
    node_public_key
    |> subset_from_address
    |> Subset.add_end_of_node_sync(%EndOfNodeSync{
      public_key: node_public_key,
      timestamp: timestamp
    })
  end

  @spec get_summary(binary(), DateTime.t()) :: {:ok, Summary.t()} | {:error, :not_found}
  defdelegate get_summary(subset, date), to: DB, as: :get_beacon_summary

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
  Get the beacon chain slot from the given subset and date
  """
  @spec get_slot(binary(), DateTime.t()) :: {:ok, Slot.t()} | {:error, :not_found}
  defdelegate get_slot(subset, date), to: DB, as: :get_beacon_slot

  @doc """
  Process a new incoming beacon slot to register into the DB if the checks pass.

  If a slot was already persisted it will not rewrite it unless the new bring more new validations
  """
  @spec register_slot(Slot.t()) ::
          :ok
          | {:error, :not_storage_node}
          | {:invalid_previous_hash}
          | {:error, :invalid_signatures}
  def register_slot(slot = %Slot{}) do
    case validate_new_slot(slot) do
      :ok ->
        do_slot_registration(slot)

      {:error, reason} = e ->
        Logger.error("Invalid Beacon Slot - #{inspect(reason)}")
        e
    end
  end

  defp validate_new_slot(
         slot = %Slot{
           transaction_summaries: transaction_summaries,
           end_of_node_synchronizations: end_of_node_sync
         }
       ) do
    cond do
      !SummaryValidation.storage_node?(slot) ->
        {:error, :not_storage_node}

      !SummaryValidation.valid_previous_hash?(slot) ->
        {:error, :invalid_previous_hash}

      !SummaryValidation.valid_signatures?(slot) ->
        {:error, :invalid_signatures}

      !SummaryValidation.valid_transaction_summaries?(transaction_summaries) ->
        {:error, :invalid_transaction_summaries}

      !SummaryValidation.valid_end_of_node_sync?(end_of_node_sync) ->
        {:error, :invalid_end_of_node_sync}

      true ->
        :ok
    end
  end

  defp do_slot_registration(
         slot = %Slot{subset: subset, slot_time: slot_time, validation_signatures: new_signatures}
       ) do
    case DB.get_beacon_slot(subset, slot_time) do
      {:ok, %Slot{validation_signatures: signatures}} ->
        if map_size(signatures) < map_size(new_signatures) do
          DB.register_beacon_slot(slot)
        else
          :ok
        end

      {:error, :not_found} ->
        DB.register_beacon_slot(slot)
    end
  end

  @doc """
  Add a proof of the beacon slot for validation during the beacon slot consensus and synchronization
  """
  @spec add_slot_proof(binary(), binary(), Crypto.key(), binary()) :: :ok
  defdelegate add_slot_proof(subset, digest, node_public_key, signature), to: Subset

  @doc """
  Return the previous summary time
  """
  @spec previous_summary_time(DateTime.t()) :: DateTime.t()
  defdelegate previous_summary_time(date_from), to: SummaryTimer, as: :previous_summary

  @doc """
  Load the transaction in the beacon chain context
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{type: :node, previous_public_key: previous_public_key}) do
    first_public_key = TransactionChain.get_first_public_key(previous_public_key)

    if Crypto.node_public_key(0) == first_public_key do
      start_schedulers()
    else
      :ok
    end
  end

  def load_transaction(_), do: :ok

  @doc """
  Start the beacon chain timers
  """
  @spec start_schedulers() :: :ok
  def start_schedulers do
    SlotTimer.start_scheduler()
    SummaryTimer.start_scheduler()
  end
end
