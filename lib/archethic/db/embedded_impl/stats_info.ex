defmodule ArchEthic.DB.EmbeddedImpl.StatsInfo do
  @moduledoc false

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Return the last number of transaction in the network (from the previous self-repair cycles)
  """
  @spec get_nb_transactions() :: non_neg_integer()
  def get_nb_transactions do
    GenServer.call(__MODULE__, :get_nb_transactions)
  end

  @doc """
  Return tps from the last self-repair cycle
  """
  @spec get_tps() :: float()
  def get_tps do
    GenServer.call(__MODULE__, :get_tps)
  end

  @doc """
  Register the new stats from a self-repair cycle
  """
  @spec new_stats(DateTime.t(), float(), non_neg_integer()) :: :ok
  def new_stats(date = %DateTime{}, tps, nb_transactions)
      when is_float(tps) and is_integer(nb_transactions) and nb_transactions >= 0 do
    GenServer.cast(__MODULE__, {:new_stats, date, tps, nb_transactions})
  end

  def register_p2p_summaries(node_public_key, date, available?, avg_availability)
      when is_binary(node_public_key) and is_boolean(available?) and is_float(avg_availability) do
    GenServer.cast(
      __MODULE__,
      {:new_p2p_summaries, node_public_key, date, available?, avg_availability}
    )
  end

  @doc """
  Return the last P2P summary from the last self-repair cycle
  """
  @spec get_last_p2p_summaries :: %{
          (node_public_key :: Crypto.key()) => {
            available? :: boolean(),
            average_availability :: float()
          }
        }
  def get_last_p2p_summaries do
    GenServer.call(__MODULE__, :get_p2p_summaries)
  end

  def init(opts) do
    db_path = Keyword.get(opts, :path)
    filepath = Path.join(db_path, "stats.dat")
    fd = File.open!(filepath, [:binary, :read, :append])

    {:ok, %{fd: fd, filepath: filepath, tps: 0.0, nb_transactions: 0},
     {:continue, :load_from_file}}
  end

  def handle_continue(:load_from_file, state = %{filepath: filepath, fd: fd}) do
    if File.exists?(filepath) do
      {tps, nb_transactions} = load_from_file(fd)

      new_state =
        state
        |> Map.put(:tps, tps)
        |> Map.put(:nb_transactions, nb_transactions)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  defp load_from_file(fd, acc \\ {0.0, 0}) do
    # Read each stats entry 16 bytes: 4(timestamp) + 8(tps) + 4(nb transactions)
    case :file.read(fd, 16) do
      {:ok, <<_timestamp::32, tps::float-64, nb_transactions::32>>} ->
        {_, prev_nb_transactions} = acc
        load_from_file(fd, {tps, prev_nb_transactions + nb_transactions})

      :eof ->
        acc
    end
  end

  def handle_call(:get_nb_transactions, _, state = %{nb_transactions: nb_transactions}) do
    {:reply, nb_transactions, state}
  end

  def handle_call(:get_tps, _, state = %{tps: tps}) do
    {:reply, tps, state}
  end

  def handle_cast({:new_stats, date, tps, nb_transactions}, state = %{fd: fd}) do
    append_to_file(fd, date, tps, nb_transactions)

    new_state =
      state
      |> Map.put(:tps, tps)
      |> Map.update!(:nb_transactions, &(&1 + nb_transactions))

    {:noreply, new_state}
  end

  defp append_to_file(fd, date, tps, nb_transactions) do
    IO.binwrite(fd, <<DateTime.to_unix(date)::32, tps::float-64, nb_transactions::32>>)
  end
end
