defmodule Uniris.OracleChain do
  @moduledoc """
  Manage network based oracle to verify, add new oracle transaction in the system and request last udpate.any()

  UCO Price is the first network Oracle and it's used for many algorithms such as: transaction fee, node rewards, smart contracts
  """

  alias __MODULE__.MemTable
  alias __MODULE__.MemTableLoader
  alias __MODULE__.Services
  alias __MODULE__.Summary

  alias Uniris.PubSub

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  @doc """
  Determines if the oracle transaction is valid.

  This operation will check the data from the service providers
  """
  @spec valid_services_content?(binary()) :: boolean()
  def valid_services_content?(content) when is_binary(content) do
    with {:ok, data} <- Jason.decode(content),
         true <- Services.verify_correctness?(data) do
      true
    else
      {:error, _} ->
        false

      false ->
        false
    end
  end

  @doc """
  Determines if the oracle summary is valid.

  This operation will check the data from the previous oracle transactions
  """
  @spec valid_summary?(binary(), list(Transaction.t())) :: boolean()
  def valid_summary?(content, oracle_chain) when is_binary(content) do
    with {:ok, data} <- Jason.decode(content),
         true <-
           %Summary{transactions: oracle_chain, aggregated: parse_summary_data(data)}
           |> Summary.verify?() do
      true
    else
      {:error, _} ->
        true

      false ->
        false
    end
  end

  defp parse_summary_data(data) do
    Enum.map(data, fn {timestamp, service_data} ->
      with {timestamp, _} <- Integer.parse(timestamp),
           {:ok, datetime} <- DateTime.from_unix(timestamp),
           {:ok, data} <- Services.parse_data(service_data) do
        {datetime, data}
      else
        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.into(%{})
  end

  @doc """
  Load the transaction in the memtable
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{type: :oracle, data: %TransactionData{content: content}}) do
    MemTableLoader.load_transaction(tx)
    PubSub.notify_new_oracle_data(content)
  end

  def load_transaction(tx = %Transaction{type: :oracle_summary}),
    do: MemTableLoader.load_transaction(tx)

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
