defmodule Archethic.OracleChain do
  @moduledoc """
  Manage network based oracle to verify, add new oracle transaction in the system and request last udpate.any()

  UCO Price is the first network Oracle and it's used for many algorithms such as: transaction fee, node rewards, smart contracts
  """

  alias __MODULE__.MemTable
  alias __MODULE__.MemTableLoader
  alias __MODULE__.Scheduler
  alias __MODULE__.Services
  alias __MODULE__.Summary

  alias Archethic.TransactionChain.Transaction

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.Scheduler, as: CronScheduler

  require Logger

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
      {:error, reason} ->
        Logger.debug("Cannot decode oracle content: #{inspect(reason)} - #{inspect(content)}")
        false

      false ->
        false
    end
  end

  @doc """
  Determines if the oracle summary is valid.

  This operation will check the data from the previous oracle transactions
  """
  @spec valid_summary?(binary(), Enumerable.t() | list(Transaction.t())) :: boolean()
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
  def load_transaction(tx = %Transaction{type: :oracle}) do
    MemTableLoader.load_transaction(tx)
  end

  def load_transaction(tx = %Transaction{type: :oracle_summary}) do
    MemTableLoader.load_transaction(tx)
  end

  def load_transaction(%Transaction{}), do: :ok

  @doc """
  Get the UCO price at the given date

  Returns the EUR and USD price

  If the price is not found, it use the default value at $0.07

  """
  @spec get_uco_price(DateTime.t()) :: list({binary(), float()})
  def get_uco_price(date = %DateTime{}) do
    case MemTable.get_oracle_data("uco", date) do
      {:ok, prices} ->
        Enum.map(prices, fn {pair, price} -> {String.to_existing_atom(pair), price} end)

      _ ->
        [eur: 0.05, usd: 0.07]
    end
  end

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(Scheduler)
    |> Scheduler.config_change()
  end

  @doc """
  Return the list of OracleChain summary dates from a given date
  """
  @spec summary_dates(DateTime.t()) :: Enumerable.t()
  def summary_dates(date_from = %DateTime{}) do
    Scheduler.get_summary_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_previous_run_dates(DateTime.utc_now() |> DateTime.to_naive())
    |> Stream.take_while(fn datetime ->
      datetime
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.compare(date_from) == :gt
    end)
    |> Stream.map(&DateTime.from_naive!(&1, "Etc/UTC"))
  end

  @doc """
  Return the next oracle summary date
  """
  @spec next_summary_date(DateTime.t()) :: DateTime.t()
  def next_summary_date(date_from = %DateTime{}) do
    Scheduler.get_summary_interval()
    |> CronParser.parse!(true)
    |> CronScheduler.get_next_run_date!(DateTime.to_naive(date_from))
    |> DateTime.from_naive!("Etc/UTC")
  end
end
