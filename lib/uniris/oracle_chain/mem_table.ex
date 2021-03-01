defmodule Uniris.OracleChain.MemTable do
  @moduledoc false

  use GenServer

  @doc """
  Start a Oracle mem table

  ## Examples

      iex> {:ok, _} = MemTable.start_link()
      iex> :ets.tab2list(:uniris_oracle)
      []
  """
  @spec start_link(list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    :ets.new(:uniris_oracle, [:set, :named_table, :public, read_concurrency: true])
    {:ok, []}
  end

  @doc """
  Reference some data for an oracle type

  ## Examples

      iex> {:ok, _} = MemTable.start_link()
      iex> MemTable.add_oracle_data("uco", %{ "eur" => 0.02 })
      iex> :ets.tab2list(:uniris_oracle)
      [ {"uco", %{ "eur" => 0.02 }}]
  """
  @spec add_oracle_data(any(), map()) :: :ok
  def add_oracle_data(type, data) when is_map(data) do
    true = :ets.insert(:uniris_oracle, {type, data})
    :ok
  end

  @doc """
  Get the referenced data for an oracle type

   ## Examples

      iex> {:ok, _} = MemTable.start_link()
      iex> MemTable.add_oracle_data("uco", %{ "eur" => 0.02 })
      iex> MemTable.get_oracle_data("uco")
      {:ok, %{"eur" => 0.02}}
  """
  @spec get_oracle_data(any()) :: {:ok, map()} | {:error, :not_found}
  def get_oracle_data(type) do
    case :ets.lookup(:uniris_oracle, type) do
      [] ->
        {:error, :not_found}

      [{_, data}] ->
        {:ok, data}
    end
  end
end
