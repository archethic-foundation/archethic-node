defmodule Archethic.DB.EmbeddedImpl.ChainWriter do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.BeaconChain.Summary

  alias Archethic.Crypto

  alias Archethic.DB.EmbeddedImpl.Encoding
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.ChainWriterSupervisor

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  def start_link(arg \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @doc """
  Append a transaction to a file for the given genesis address
  """
  @spec append_transaction(binary(), Transaction.t()) :: :ok
  def append_transaction(genesis_address, tx = %Transaction{}) do
    via_tuple = {:via, PartitionSupervisor, {ChainWriterSupervisor, genesis_address}}
    GenServer.call(via_tuple, {:append_tx, genesis_address, tx})
  end

  @doc """
  write an io transaction in a file name by it's address
  """
  @spec write_io_transaction(Transaction.t(), String.t()) :: :ok
  def write_io_transaction(tx = %Transaction{address: address}, db_path) do
    start = System.monotonic_time()

    filename = io_path(db_path, address)

    data = Encoding.encode(tx)

    File.write!(
      filename,
      data,
      [:exclusive, :binary]
    )

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_io_transaction"
    })
  end

  @doc """
  Write a beacon summary in a new file
  """
  @spec write_beacon_summary(Summary.t(), binary()) :: :ok
  def write_beacon_summary(
        summary = %Summary{subset: subset, summary_time: summary_time},
        db_path
      ) do
    start = System.monotonic_time()

    summary_address = Crypto.derive_beacon_chain_address(subset, summary_time, true)

    filename = beacon_path(db_path, summary_address)

    data = Summary.serialize(summary) |> Utils.wrap_binary()

    File.write!(
      filename,
      data,
      [:exclusive, :binary]
    )

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_beacon_summary"
    })
  end

  @doc """
  Write a beacon summaries aggregate in a new file
  """
  @spec write_beacon_summaries_aggregate(SummaryAggregate.t(), String.t()) :: :ok
  def write_beacon_summaries_aggregate(
        aggregate = %SummaryAggregate{summary_time: summary_time},
        db_path
      )
      when is_binary(db_path) do
    start = System.monotonic_time()

    filename = beacon_aggregate_path(db_path, summary_time)

    data =
      aggregate
      |> SummaryAggregate.serialize()
      |> Utils.wrap_binary()

    File.write!(filename, data, [:binary])

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_beacon_summaries_aggregate"
    })
  end

  def init(arg) do
    db_path = Keyword.get(arg, :path)

    {:ok, %{db_path: db_path}}
  end

  @doc """
  Create all folder needed for DB
  """
  @spec setup_folders!(binary()) :: :ok
  def setup_folders!(path) do
    File.mkdir_p!(path)

    path
    |> base_chain_path()
    |> File.mkdir_p!()

    path
    |> base_io_path()
    |> File.mkdir_p!()

    path
    |> base_beacon_path()
    |> File.mkdir_p!()

    path
    |> base_beacon_aggregate_path()
    |> File.mkdir_p!()
  end

  def handle_call(
        {:append_tx, genesis_address, tx},
        _from,
        state = %{db_path: db_path}
      ) do
    write_transaction(genesis_address, tx, db_path)
    {:reply, :ok, state}
  end

  def handle_call(
        {:write_io_transaction, tx},
        _from,
        state = %{db_path: db_path}
      ) do
    write_io_transaction(tx, db_path)
    {:reply, :ok, state}
  end

  defp write_transaction(genesis_address, tx, db_path) do
    start = System.monotonic_time()

    filename = chain_path(db_path, genesis_address)

    data = Encoding.encode(tx)

    File.write!(
      filename,
      data,
      [:append, :binary]
    )

    index_transaction(tx, genesis_address, byte_size(data), db_path)

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "write_transaction"
    })
  end

  defp index_transaction(
         %Transaction{
           address: tx_address,
           type: tx_type,
           previous_public_key: previous_public_key,
           validation_stamp: %ValidationStamp{timestamp: timestamp}
         },
         genesis_address,
         encoded_size,
         db_path
       ) do
    start = System.monotonic_time()

    ChainIndex.add_tx(tx_address, genesis_address, encoded_size, db_path)
    ChainIndex.add_tx_type(tx_type, tx_address, db_path)
    ChainIndex.set_last_chain_address_stored(genesis_address, tx_address, db_path)
    ChainIndex.set_last_chain_address(genesis_address, tx_address, timestamp, db_path)
    ChainIndex.set_public_key(genesis_address, previous_public_key, timestamp, db_path)

    :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
      query: "index_transaction"
    })
  end

  @doc """
  Return the path of the chain storage location
  """
  @spec chain_path(String.t(), binary()) :: String.t()
  def chain_path(db_path, genesis_address)
      when is_binary(genesis_address) and is_binary(db_path) do
    Path.join([base_chain_path(db_path), Base.encode16(genesis_address)])
  end

  @doc """
  Return the path of the io storage location
  """
  @spec io_path(String.t(), binary()) :: String.t()
  def io_path(db_path, address)
      when is_binary(address) and is_binary(db_path) do
    Path.join([base_io_path(db_path), Base.encode16(address)])
  end

  @doc """
  Return the chain base path
  """
  @spec base_chain_path(String.t()) :: String.t()
  def base_chain_path(db_path) do
    Path.join([db_path, "chains"])
  end

  @doc """
  Return the io base path
  """
  @spec base_io_path(String.t()) :: String.t()
  def base_io_path(db_path) do
    Path.join([db_path, "io"])
  end

  @doc """
  Return the path of the beacon summary storage location
  """
  @spec beacon_path(String.t(), binary()) :: String.t()
  def beacon_path(db_path, summary_address)
      when is_binary(summary_address) and is_binary(db_path) do
    Path.join([base_beacon_path(db_path), Base.encode16(summary_address)])
  end

  @doc """
  Return the path of the beacon summary aggregate storage location
  """
  @spec beacon_aggregate_path(String.t(), DateTime.t()) :: String.t()
  def beacon_aggregate_path(db_path, date = %DateTime{}) when is_binary(db_path) do
    Path.join([base_beacon_aggregate_path(db_path), date |> DateTime.to_unix() |> to_string()])
  end

  @doc """
  Return the beacon summary base path
  """
  @spec base_beacon_path(String.t()) :: String.t()
  def base_beacon_path(db_path) do
    Path.join([db_path, "beacon_summary"])
  end

  @doc """
  Return the beacon summaries aggregate base path
  """
  @spec base_beacon_aggregate_path(String.t()) :: String.t()
  def base_beacon_aggregate_path(db_path) do
    Path.join([db_path, "beacon_aggregate"])
  end

  @doc """
  Return the migration file path
  """
  @spec migration_file_path(String.t()) :: String.t()
  def migration_file_path(db_path) do
    Path.join([db_path, "migration"])
  end
end
