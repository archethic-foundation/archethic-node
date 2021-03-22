defmodule Uniris.OracleChain do
  @moduledoc """
  Manage network based oracle to verify, add new oracle transaction in the system and request last udpate.any()

  UCO Price is the first network Oracle and it's used for many algorithms such as: transaction fee, node rewards, smart contracts
  """

  alias __MODULE__.MemTable
  alias __MODULE__.MemTableLoader
  alias __MODULE__.Scheduler
  alias __MODULE__.Services

  alias Uniris.Crypto

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  require Logger

  @doc """
  Start the oracle scheduling
  """
  @spec start_scheduling() :: :ok
  defdelegate start_scheduling, to: Scheduler

  @doc """
  Determines if the oracle transaction is valid.

  This operation will check the data from the service providers
  """
  @spec verify?(Transaction.t()) :: boolean()
  def verify?(%Transaction{
        type: :oracle,
        data: %TransactionData{content: content}
      }) do
    case Jason.decode(content) do
      {:ok, data} ->
        do_verify?(data)

      _ ->
        Logger.error("Invalid oracle content")
        false
    end
  end

  def verify?(%Transaction{
        type: :oracle_summary,
        data: %{content: content},
        previous_public_key: previous_public_key
      }) do
    case Jason.decode(content) do
      {:ok, data} ->
        do_verify_summary?(data, Crypto.hash(previous_public_key))

      _ ->
        Logger.error("Invalid oracle content")
        false
    end
  end

  defp do_verify?(data) when is_map(data) do
    correctness? = Services.verify_correctness?(data)

    unless correctness? do
      Logger.error("Oracle data incorrect")
    end

    correctness?
  end

  defp do_verify_summary?(data, previous_address) when is_map(data) do
    stored_digest =
      TransactionChain.get(previous_address, [:timestamp, data: [:content]])
      |> Enum.map(fn %Transaction{timestamp: timestamp, data: %TransactionData{content: content}} ->
        data = Jason.decode!(content)
        {DateTime.to_unix(timestamp), data}
      end)
      |> Enum.into(%{})
      |> Jason.encode!()
      |> Crypto.hash()

    data_digest = data |> Jason.encode!() |> Crypto.hash()
    stored_digest == data_digest
  end

  @doc """
  Load the transaction in the memtable
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{type: :oracle}), do: MemTableLoader.load_transaction(tx)

  def load_transaction(tx = %Transaction{type: :oracle_summary}),
    do: MemTableLoader.load_transaction(tx)

  def load_transaction(%Transaction{type: :node, previous_public_key: previous_public_key}) do
    first_public_key = TransactionChain.get_first_public_key(previous_public_key)

    if Crypto.node_public_key(0) == first_public_key do
      start_scheduling()
    else
      :ok
    end
  end

  def load_transaction(%Transaction{}), do: :ok

  @doc """
  Get the last UCO price in euro
  """
  @spec get_uco_price() :: list({binary(), float()})
  def get_uco_price do
    case MemTable.get_oracle_data("uco") do
      {:ok, prices} ->
        Enum.map(prices, fn {pair, price} -> {String.to_existing_atom(pair), price} end)

      _ ->
        [eur: 0.0, usd: 0.0]
    end
  end
end
