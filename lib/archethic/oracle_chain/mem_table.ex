defmodule Archethic.OracleChain.MemTable do
  @moduledoc false

  use GenServer
  @vsn 1

  @oracle_data :archethic_oracle
  @oracle_gen_addr :archethic_oracle_gen_addr

  require Logger

  @doc """
  Start a Oracle mem table

  ## Examples

      iex> {:ok, _} = MemTable.start_link()
      ...> :ets.tab2list(:archethic_oracle)
      []
  """
  @spec start_link(list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    :ets.new(@oracle_data, [:ordered_set, :named_table, :public, read_concurrency: true])

    :ets.new(@oracle_gen_addr, [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    {:ok, []}
  end

  @doc """
  Reference some data for an oracle type

  ## Examples

      iex> {:ok, _} = MemTable.start_link()
      ...> MemTable.add_oracle_data("uco", %{"eur" => 0.02}, ~U[2021-06-04 10:10:00Z])
      ...> :ets.tab2list(:archethic_oracle)
      [{{1_622_801_400, "uco"}, %{"eur" => 0.02}}]
  """
  @spec add_oracle_data(any(), map(), DateTime.t()) :: :ok
  def add_oracle_data(type, data, date = %DateTime{}) when is_map(data) do
    timestamp =
      date
      |> DateTime.to_unix()

    true = :ets.insert(:archethic_oracle, {{timestamp, type}, data})
    :ok
  end

  @doc """
  Get the referenced data for an oracle type for a given date

  ## Examples

      iex> {:ok, _} = MemTable.start_link()
      ...> MemTable.add_oracle_data("uco", %{"eur" => 0.02}, ~U[2021-06-04 10:00:00Z])
      ...> MemTable.add_oracle_data("uco", %{"eur" => 0.04}, ~U[2021-06-04 15:00:00Z])
      ...> MemTable.get_oracle_data("uco", ~U[2021-06-04 10:10:00Z])
      {:ok, %{"eur" => 0.02}, ~U[2021-06-04 10:00:00Z]}
      iex> MemTable.get_oracle_data("uco", ~U[2021-06-04 20:10:40Z])
      {:ok, %{"eur" => 0.04}, ~U[2021-06-04 15:00:00Z]}

  """
  @spec get_oracle_data(any(), DateTime.t()) ::
          {:ok, data :: map(), oracle_datetime :: DateTime.t()} | {:error, :not_found}
  def get_oracle_data(type, date = %DateTime{}) do
    timestamp =
      date
      |> DateTime.to_unix()

    case :ets.prev(:archethic_oracle, {timestamp, type}) do
      :"$end_of_table" ->
        {:error, :not_found}

      key = {time, _} ->
        [{_, data}] = :ets.lookup(:archethic_oracle, key)
        {:ok, data, DateTime.from_unix!(time)}
    end
  end

  @spec put_addr(binary(), DateTime.t()) :: :ok
  def put_addr(address, datetime = %DateTime{}) when is_binary(address) do
    case :ets.lookup(@oracle_gen_addr, :current_gen_addr) do
      [] ->
        true = :ets.insert(@oracle_gen_addr, {:current_gen_addr, address, datetime})

        :ok

      [{:current_gen_addr, prev_address, prev_datetime}] ->
        true = :ets.insert(@oracle_gen_addr, {:prev_gen_addr, prev_address, prev_datetime})

        true = :ets.insert(@oracle_gen_addr, {:current_gen_addr, address, datetime})

        :ok
    end
  end

  @doc """
  Get the referenced data for an oracle type for a given date
  ## Examples
      iex> {:ok, _} = MemTable.start_link()
      ...> MemTable.put_addr("@OracleSummaryGenAddr56", ~U[2021-06-04 10:00:00Z])
      ...> MemTable.get_addr()
      %{
        current: {"@OracleSummaryGenAddr56", ~U[2021-06-04 10:00:00Z]},
        prev: {nil, nil}
      }
      iex> MemTable.put_addr("@OracleSummaryGenAddr57", ~U[2021-06-04 11:00:00Z])
      ...> MemTable.get_addr()
      %{
        current: {"@OracleSummaryGenAddr57", ~U[2021-06-04 11:00:00Z]},
        prev: {"@OracleSummaryGenAddr56", ~U[2021-06-04 10:00:00Z]}
      }
      iex> MemTable.put_addr("@OracleSummaryGenAddr58", ~U[2021-06-04 12:00:00Z])
      ...> MemTable.get_addr()
      %{
        current: {"@OracleSummaryGenAddr58", ~U[2021-06-04 12:00:00Z]},
        prev: {"@OracleSummaryGenAddr57", ~U[2021-06-04 11:00:00Z]}
      }
  """
  @spec get_addr() ::
          %{
            current: {binary(), DateTime.t()},
            prev: {binary(), DateTime.t()}
          }
          | nil
  def get_addr() do
    curr_addr = :ets.lookup(@oracle_gen_addr, :current_gen_addr)
    prev_addr = :ets.lookup(@oracle_gen_addr, :prev_gen_addr)

    case {curr_addr, prev_addr} do
      {[], _} ->
        nil

      {[curr], []} ->
        %{
          current: {curr |> elem(1), curr |> elem(2)},
          prev: {nil, nil}
        }

      {[curr], [prev]} ->
        %{
          current: {curr |> elem(1), curr |> elem(2)},
          prev: {prev |> elem(1), prev |> elem(2)}
        }
    end
  end
end
