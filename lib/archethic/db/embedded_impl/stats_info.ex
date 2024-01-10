defmodule Archethic.DB.EmbeddedImpl.StatsInfo do
  @moduledoc false

  use GenServer
  @vsn 1

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
  Return burned fees from the last self-repair cycle
  """
  @spec get_burned_fees() :: non_neg_integer()
  def get_burned_fees do
    GenServer.call(__MODULE__, :get_burned_fees)
  end

  @doc """
  Register the new stats from a self-repair cycle
  """
  @spec new_stats(DateTime.t(), float(), non_neg_integer(), non_neg_integer()) :: :ok
  def new_stats(date = %DateTime{}, tps, nb_transactions, burned_fees)
      when is_float(tps) and is_integer(nb_transactions) and nb_transactions >= 0 and
             is_integer(burned_fees) and burned_fees >= 0 do
    GenServer.cast(__MODULE__, {:new_stats, date, tps, nb_transactions, burned_fees})
  end

  def init(opts) do
    db_path = Keyword.get(opts, :path)
    filepath = Path.join(db_path, "stats")

    {last_update, tps, nb_transactions, burned_fees} =
      case File.read(filepath) do
        {:ok, <<timestamp::32, tps::float-64, nb_transactions::64, burned_fees::64>>} ->
          {DateTime.from_unix!(timestamp), tps, nb_transactions, burned_fees}

        _ ->
          {DateTime.from_unix!(0), 0.0, 0, 0}
      end

    state =
      %{:filepath => filepath}
      |> Map.put(:last_update, last_update)
      |> Map.put(:tps, tps)
      |> Map.put(:nb_transactions, nb_transactions)
      |> Map.put(:burned_fees, burned_fees)

    {:ok, state}
  end

  def handle_call(:get_nb_transactions, _, state = %{nb_transactions: nb_transactions}) do
    {:reply, nb_transactions, state}
  end

  def handle_call(:get_tps, _, state = %{tps: tps}) do
    {:reply, tps, state}
  end

  def handle_call(:get_burned_fees, _, state = %{burned_fees: burned_fees}) do
    {:reply, burned_fees, state}
  end

  def handle_cast(
        {:new_stats, date, tps, nb_transactions, burned_fees},
        state = %{last_update: last_update, filepath: filepath, nb_transactions: prev_nb_tx}
      ) do
    new_state =
      if DateTime.compare(date, last_update) == :gt do
        new_nb_transactions = prev_nb_tx + nb_transactions

        File.write!(
          filepath,
          <<DateTime.to_unix(date)::32, tps::float-64, new_nb_transactions::64, burned_fees::64>>
        )

        state
        |> Map.put(:tps, tps)
        |> Map.put(:nb_transactions, new_nb_transactions)
        |> Map.put(:burned_fees, burned_fees)
      else
        state
      end

    {:noreply, new_state}
  end

  def code_change(_, state, _), do: {:ok, state}
end
