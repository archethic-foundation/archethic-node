defmodule Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics do
  @moduledoc false

  use GenServer

  alias Uniris.PubSub
  alias Uniris.Utils

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    init_dump_dir()

    unless File.exists?(dump_filename(:uniris_tps)) do
      :ets.new(:uniris_tps, [:named_table, :ordered_set, :public, read_concurrency: true])
    end

    unless File.exists?(dump_filename(:uniris_stats)) do
      :ets.new(:uniris_stats, [:named_table, :set, :public, read_concurrency: true])
    end

    :ets.file2tab(dump_filename(:uniris_tps) |> String.to_charlist())
    :ets.file2tab(dump_filename(:uniris_stats) |> String.to_charlist())

    {:ok, []}
  end

  @doc """
  Return the latest TPS record

  ## Examples

      iex> NetworkStatistics.start_link()
      iex> NetworkStatistics.register_tps(~U[2021-02-02 00:00:00Z], 10.0, 100)
      iex> NetworkStatistics.register_tps(~U[2021-02-03 00:00:00Z], 100.0, 1000)
      iex> NetworkStatistics.get_latest_tps()
      100.0
  """
  @spec get_latest_tps :: float()
  def get_latest_tps do
    case :ets.last(:uniris_tps) do
      :"$end_of_table" ->
        0.0

      key ->
        [{_, tps, _nb_transactions}] = :ets.lookup(:uniris_tps, key)
        tps
    end
  end

  @doc """
  Returns the number of transactions
  """
  @spec get_nb_transactions() :: non_neg_integer()
  def get_nb_transactions do
    case :ets.lookup(:uniris_stats, :nb_transactions) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  @doc """
  Increment the number of transactions by the given number
  """
  @spec increment_number_transactions(non_neg_integer()) :: :ok
  def increment_number_transactions(nb \\ 1) when is_integer(nb) and nb >= 0 do
    new_nb = :ets.update_counter(:uniris_stats, :nb_transactions, nb, {0, 0})
    dump_table(:uniris_stats)
    PubSub.notify_new_transaction_number(new_nb)
    :ok
  end

  @doc """
  Register a new TPS for the given date
  """
  @spec register_tps(DateTime.t(), float(), non_neg_integer()) :: :ok
  def register_tps(date = %DateTime{}, tps, nb_transactions)
      when is_float(tps) and tps >= 0.0 and is_integer(nb_transactions) and nb_transactions >= 0 do
    Logger.info(
      "TPS #{tps} on #{Utils.time_to_string(date)} with #{nb_transactions} transactions"
    )

    true = :ets.insert(:uniris_tps, {date, tps, nb_transactions})
    :ok = dump_table(:uniris_tps)
    PubSub.notify_new_tps(tps)
    :ok
  end

  defp dump_table(table) when is_atom(table) do
    filename =
      table
      |> dump_filename()
      |> String.to_charlist()

    :ets.tab2file(table, filename)
  end

  defp dump_filename(table) do
    Path.join(dump_dirname(), Atom.to_string(table))
  end

  defp init_dump_dir do
    File.mkdir_p!(dump_dirname())
  end

  defp dump_dirname do
    dump_dir = Application.get_env(:uniris, __MODULE__) |> Keyword.fetch!(:dump_dir)
    Utils.mut_dir(dump_dir)
  end
end
