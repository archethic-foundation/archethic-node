defmodule Uniris.DB.CassandraImpl do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.Summary

  alias Uniris.DBImpl

  alias __MODULE__.CQL
  alias __MODULE__.SchemaMigrator

  alias Uniris.TransactionChain.Transaction

  alias Uniris.Utils

  @behaviour DBImpl

  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :permanent}
  end

  @doc """
  Initialize the connection pool and start the migrations
  """
  @spec start_link(Keyword.t()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    nodes = Keyword.get(opts, :nodes, ["127.0.0.1:9042"])

    {:ok, pid} =
      Xandra.start_link(
        name: :xandra_conn,
        pool_size: 10,
        nodes: nodes
      )

    :ok = SchemaMigrator.run()
    {:ok, pid}
  end

  @impl DBImpl
  def migrate do
    SchemaMigrator.run()
  end

  @doc """
  List the transactions
  """
  @impl DBImpl
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    :xandra_conn
    |> Xandra.stream_pages!(list_transactions_query(fields), _params = [], page_size: 100)
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_result_to_transaction/1)
  end

  @impl DBImpl
  @doc """
  Retrieve a transaction by address and project the requested fields
  """
  @spec get_transaction(binary(), list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    prepared = Xandra.prepare!(:xandra_conn, get_transaction_query(fields))

    result =
      :xandra_conn
      |> Xandra.execute!(prepared, [address])
      |> Enum.at(0)

    case result do
      nil ->
        {:error, :transaction_not_exists}

      tx ->
        {:ok, format_result_to_transaction(tx)}
    end
  end

  @impl DBImpl
  @doc """
  Fetch the transaction chain by address and project the requested fields from the transactions
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    prepared = Xandra.prepare!(:xandra_conn, get_transaction_chain_query())

    :xandra_conn
    |> Xandra.stream_pages!(prepared, %{"chain_address" => address})
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{"transaction_address" => address} ->
      {:ok, tx} = get_transaction(address, fields)
      tx
    end)
  end

  @impl DBImpl
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    prepared = Xandra.prepare!(:xandra_conn, insert_transaction_query())
    {:ok, _} = Xandra.execute(:xandra_conn, prepared, transaction_write_parameters(tx))
    :ok
  end

  @impl DBImpl
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    transaction_prepared = Xandra.prepare!(:xandra_conn, insert_transaction_query())
    chain_prepared = Xandra.prepare!(:xandra_conn, insert_transaction_chain_query())

    chain_size = Enum.count(chain)

    chain_address =
      chain
      |> Stream.map(& &1.address)
      |> Enum.at(0)

    Task.async_stream(chain, fn tx ->
      {:ok, _} =
        Xandra.execute(:xandra_conn, transaction_prepared, transaction_write_parameters(tx))

      {:ok, _} =
        Xandra.execute(
          :xandra_conn,
          chain_prepared,
          transaction_chain_write_parameters(chain_address, tx, chain_size)
        )
    end)
    |> Stream.run()
  end

  defp transaction_write_parameters(tx = %Transaction{}) do
    tx
    |> Transaction.to_map()
    |> Utils.stringify_keys()
  end

  defp transaction_chain_write_parameters(
         chain_address,
         tx = %Transaction{},
         chain_size
       ) do
    %{
      "chain_address" => chain_address,
      "transaction_address" => tx.address,
      "size" => chain_size,
      "timestamp" => tx.timestamp
    }
  end

  defp format_result_to_transaction(res) do
    res
    |> Utils.atomize_keys(true)
    |> Transaction.from_map()
  end

  defp insert_transaction_query do
    """
    INSERT INTO uniris.transactions(
      address,
      type,
      timestamp,
      data,
      previous_public_key,
      previous_signature,
      origin_signature,
      validation_stamp,
      cross_validation_stamps)
    VALUES(
      :address,
      :type,
      :timestamp,
      :data,
      :previous_public_key,
      :previous_signature,
      :origin_signature,
      :validation_stamp,
      :cross_validation_stamps
    )
    """
  end

  defp insert_transaction_chain_query do
    """
    INSERT INTO uniris.transaction_chains(
      chain_address,
      size,
      transaction_address,
      timestamp)
    VALUES(
      :chain_address,
      :size,
      :transaction_address,
      :timestamp)
    """
  end

  defp get_transaction_chain_query do
    """
    SELECT transaction_address
    FROM uniris.transaction_chains
    WHERE chain_address=?
    """
  end

  defp get_transaction_query(fields) do
    "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions WHERE address=?"
  end

  defp list_transactions_query(fields) do
    "SELECT #{CQL.list_to_cql(fields)} FROM uniris.transactions"
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DBImpl
  @spec add_last_transaction_address(binary(), binary()) :: :ok
  def add_last_transaction_address(tx_address, last_address) do
    prepared_query = Xandra.prepare!(:xandra_conn, insert_chain_lookup_query())
    {:ok, _} = Xandra.execute(:xandra_conn, prepared_query, [tx_address, last_address])
    :ok
  end

  defp insert_chain_lookup_query do
    """
    INSERT INTO uniris.chain_lookup(transaction_address, last_transaction_address) VALUES(?, ?)
    """
  end

  @doc """
  List the last transaction lookups
  """
  @impl DBImpl
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    prepared = Xandra.prepare!(:xandra_conn, "SELECT * FROM uniris.chain_lookup")

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [])
    |> Stream.flat_map(& &1)
    |> Stream.map(fn %{
                       "transaction_address" => address,
                       "last_transaction_address" => last_address
                     } ->
      {address, last_address}
    end)
  end

  @impl DBImpl
  @spec register_beacon_slot(Slot.t()) :: :ok
  def register_beacon_slot(%Slot{
        subset: subset,
        slot_time: slot_time,
        previous_hash: previous_hash,
        transaction_summaries: transaction_summaries,
        end_of_node_synchronizations: end_of_node_synchronizations,
        p2p_view: p2p_view,
        involved_nodes: involved_nodes,
        validation_signatures: validation_signatures
      }) do
    prepared =
      Xandra.prepare!(:xandra_conn, """
      INSERT INTO uniris.beacon_chain_slot(
        subset, 
        slot_time,
        previous_hash,
        transaction_summaries,
        end_of_node_synchronizations,
        p2p_view,
        involved_nodes,
        validation_signatures)

      VALUES (?, ?, ?, ?, ?, ?, ?, ?) 
      """)

    tx_summaries =
      case transaction_summaries do
        nil ->
          []

        _ ->
          Enum.map(transaction_summaries, fn tx_summary ->
            tx_summary
            |> TransactionSummary.to_map()
            |> Utils.stringify_keys()
          end)
      end

    end_of_node_syncs =
      case end_of_node_synchronizations do
        nil ->
          []

        _ ->
          Enum.map(end_of_node_synchronizations, fn end_of_sync ->
            end_of_sync
            |> EndOfNodeSync.to_map()
            |> Utils.stringify_keys()
          end)
      end

    p2p_view =
      case p2p_view do
        nil ->
          []

        _ ->
          p2p_view
          |> Utils.bitstring_to_integer_list()
          |> Enum.map(fn
            1 -> true
            0 -> false
          end)
      end

    involved_nodes =
      case involved_nodes do
        nil ->
          []

        _ ->
          involved_nodes
          |> Utils.bitstring_to_integer_list()
          |> Enum.map(fn
            1 -> true
            0 -> false
          end)
      end

    Xandra.execute!(:xandra_conn, prepared, [
      subset,
      slot_time,
      previous_hash,
      tx_summaries,
      end_of_node_syncs,
      p2p_view,
      involved_nodes,
      validation_signatures
    ])

    :ok
  end

  @impl DBImpl
  @spec get_beacon_slots(binary(), DateTime.t()) :: Enumerable.t()
  def get_beacon_slots(subset, from_date = %DateTime{}) when is_binary(subset) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM uniris.beacon_chain_slot WHERE subset = ? and slot_time < ?"
      )

    :xandra_conn
    |> Xandra.stream_pages!(prepared, [subset, from_date])
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_slot_result(&1))
  end

  @impl DBImpl
  @spec get_beacon_slot(binary(), DateTime.t()) :: {:ok, Slot.t()} | {:error, :not_found}
  def get_beacon_slot(subset, date = %DateTime{}) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM uniris.beacon_chain_slot WHERE subset = ? and slot_time = ?"
      )

    res =
      :xandra_conn
      |> Xandra.execute!(prepared, [subset, date])
      |> Enum.at(0)

    case res do
      nil ->
        {:error, :not_found}

      slot ->
        {:ok, format_slot_result(slot)}
    end
  end

  defp format_slot_result(%{
         "subset" => subset,
         "slot_time" => slot_time,
         "previous_hash" => previous_hash,
         "transaction_summaries" => transaction_summaries,
         "end_of_node_synchronizations" => end_of_node_synchronizations,
         "p2p_view" => p2p_view,
         "involved_nodes" => involved_nodes,
         "validation_signatures" => validation_signatures
       }) do
    %Slot{
      subset: subset,
      slot_time: slot_time,
      previous_hash: previous_hash,
      transaction_summaries:
        case transaction_summaries do
          nil ->
            []

          _ ->
            Enum.map(transaction_summaries, fn summary ->
              summary
              |> Utils.atomize_keys()
              |> TransactionSummary.from_map()
            end)
        end,
      end_of_node_synchronizations:
        case end_of_node_synchronizations do
          nil ->
            []

          _ ->
            Enum.map(end_of_node_synchronizations, fn end_of_sync ->
              end_of_sync
              |> Utils.atomize_keys()
              |> EndOfNodeSync.from_map()
            end)
        end,
      p2p_view:
        case p2p_view do
          nil ->
            <<>>

          _ ->
            p2p_view
            |> Enum.map(fn
              true -> <<1::1>>
              false -> <<0::1>>
            end)
            |> :erlang.list_to_bitstring()
        end,
      involved_nodes:
        case involved_nodes do
          nil ->
            <<>>

          _ ->
            involved_nodes
            |> Enum.map(fn
              true -> <<1::1>>
              false -> <<0::1>>
            end)
            |> :erlang.list_to_bitstring()
        end,
      validation_signatures: validation_signatures
    }
  end

  @impl DBImpl
  @spec register_beacon_summary(Summary.t()) :: :ok
  def register_beacon_summary(%Summary{
        subset: subset,
        summary_time: summary_time,
        transaction_summaries: transaction_summaries,
        end_of_node_synchronizations: end_of_node_synchronizations
      }) do
    prepared =
      Xandra.prepare!(:xandra_conn, """
      INSERT INTO uniris.beacon_chain_summary(
        subset, 
        summary_time,
        transaction_summaries,
        end_of_node_synchronizations)

      VALUES (?, ?, ?, ?) 
      """)

    tx_summaries =
      case transaction_summaries do
        nil ->
          []

        _ ->
          Enum.map(transaction_summaries, fn tx_summary ->
            tx_summary
            |> TransactionSummary.to_map()
            |> Utils.stringify_keys()
          end)
      end

    end_of_node_sync =
      case end_of_node_synchronizations do
        nil ->
          []

        _ ->
          Enum.map(end_of_node_synchronizations, fn tx_summary ->
            tx_summary
            |> EndOfNodeSync.to_map()
            |> Utils.stringify_keys()
          end)
      end

    Xandra.execute!(:xandra_conn, prepared, [
      subset,
      summary_time,
      tx_summaries,
      end_of_node_sync
    ])

    :ok
  end

  @impl DBImpl
  @spec get_beacon_summary(binary(), DateTime.t()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_beacon_summary(subset, date = %DateTime{}) do
    prepared =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM uniris.beacon_chain_summary WHERE subset = ? and summary_time = ?"
      )

    res =
      :xandra_conn
      |> Xandra.execute!(prepared, [subset, date])
      |> Enum.at(0)

    case res do
      nil ->
        {:error, :not_found}

      slot ->
        {:ok, format_summary_result(slot)}
    end
  end

  defp format_summary_result(%{
         "subset" => subset,
         "summary_time" => summary_time,
         "transaction_summaries" => transaction_summaries,
         "end_of_node_synchronizations" => end_of_node_synchronizations
       }) do
    tx_summaries =
      (transaction_summaries || [])
      |> Enum.map(fn tx_summary ->
        tx_summary
        |> Utils.atomize_keys()
        |> TransactionSummary.from_map()
      end)

    end_of_node_sync =
      (end_of_node_synchronizations || [])
      |> Enum.map(fn tx_summary ->
        tx_summary
        |> Utils.atomize_keys()
        |> EndOfNodeSync.from_map()
      end)

    %Summary{
      subset: subset,
      summary_time: summary_time,
      transaction_summaries: tx_summaries,
      end_of_node_synchronizations: end_of_node_sync
    }
  end
end
