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

  This operation will check the content on the oracle by verifying the previous hash
  and the data from the service providers
  """
  @spec verify?(Transaction.t()) :: boolean()
  def verify?(%Transaction{
        data: %TransactionData{content: content},
        previous_public_key: previous_public_key
      }) do
    previous_address = Crypto.hash(previous_public_key)

    case Jason.decode(content) do
      {:ok, map} ->
        previous_hash = Map.get(map, "previous_hash")
        data = Map.get(map, "data")

        with {:ok, %Transaction{data: %TransactionData{content: previous_content}}} <-
               TransactionChain.get_transaction(previous_address, data: [:content]),
             {:integrity, true} <-
               {:integrity, previous_hash == Base.encode16(Crypto.hash(previous_content))},
             {:correctness, true} <- {:correctness, do_verify?(data)} do
          true
        else
          {:error, _} ->
            do_verify?(data)

          {:integrity, false} ->
            Logger.error("Invalid oracle chain integrity")
            false

          {:correctness, false} ->
            false
        end

      _ ->
        Logger.error("Invalid oracle content")
        false
    end
  end

  @doc """
  Determines if a oracle summary transaction is valid

  This operation will check the content on the oracle by verifying the previous hash
  and the truth about the aggregated data
  """
  @spec verify_summary?(Transaction.t()) :: boolean()
  def verify_summary?(%Transaction{
        type: :oracle_summary,
        data: %{content: content},
        previous_public_key: previous_public_key
      }) do
    previous_address = Crypto.hash(previous_public_key)

    case Jason.decode(content) do
      {:ok, map} ->
        previous_hash = Map.get(map, "previous_hash")
        data = Map.get(map, "data")

        case TransactionChain.get_transaction(previous_address, data: [:content]) do
          {:ok, %Transaction{data: %TransactionData{content: previous_content}}} ->
            with true <- previous_hash == Base.encode16(Crypto.hash(previous_content)),
                 true <- do_verify_summary?(data) do
              true
            end

          _ ->
            do_verify_summary?(data)
        end

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

  defp do_verify_summary?(data) when is_map(data) do
    Enum.all?(data, fn {timestamp, data} ->
      with {int, _} <- Integer.parse(timestamp),
           {:ok, datetime} <- DateTime.from_unix(int),
           {pub, _} <- Crypto.derive_oracle_keypair(datetime),
           {:ok, %Transaction{data: %TransactionData{content: content}}} <-
             TransactionChain.get_transaction(Crypto.hash(pub),
               data: [:content]
             ) do
        stored_data = Jason.decode!(content) |> Map.get("data")
        data == stored_data
      else
        _ ->
          false
      end
    end)
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
