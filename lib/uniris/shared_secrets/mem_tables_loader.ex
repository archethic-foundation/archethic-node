defmodule Uniris.SharedSecrets.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Uniris.SharedSecrets.MemTables.NetworkLookup
  alias Uniris.SharedSecrets.MemTables.OriginKeyLookup
  alias Uniris.SharedSecrets.NodeRenewal
  alias Uniris.SharedSecrets.NodeRenewalScheduler

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

  @software_origin_key_regex ~r/(?<=software: ).([A-Z0-9\, ])*/
  @biometric_origin_key_regex ~r/(?<=biometric: ).([A-Z0-9\, ])*/
  @hardware_origin_key_regex ~r/(?<=hardware: ).([A-Z0-9\, ])*/

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    [
      fn ->
        TransactionChain.list_transactions_by_type(:origin_shared_secrets, [
          :type,
          data: [:content]
        ])
      end,
      fn -> TransactionChain.list_transactions_by_type(:node, [:type, :previous_public_key]) end,
      fn ->
        TransactionChain.list_transactions_by_type(:node_shared_secrets, [
          :type,
          :timestamp,
          data: [:content],
          validation_stamp: [:timestamp]
        ])
      end
    ]
    |> Task.async_stream(&load_transactions(&1.()))
    |> Stream.run()

    {:ok, []}
  end

  defp load_transactions(transactions) do
    transactions
    |> Stream.each(&load_transaction/1)
    |> Stream.run()
  end

  @doc """
  Load the transaction into the memory table
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{type: :node, previous_public_key: previous_public_key}) do
    first_public_key = TransactionChain.get_first_public_key(previous_public_key)

    unless OriginKeyLookup.has_public_key?(first_public_key) do
      # TODO: detect which family to use (ie. software, hardware)
      :ok = OriginKeyLookup.add_public_key(:software, previous_public_key)

      Logger.info("Load origin public key #{Base.encode16(previous_public_key)} - #{:software}")
    end

    :ok
  end

  def load_transaction(%Transaction{
        type: :origin_shared_secrets,
        data: %TransactionData{content: content}
      }) do
    content
    |> get_origin_public_keys_from_tx_content()
    |> Enum.each(fn {family, keys} ->
      Enum.each(keys, fn key ->
        :ok = OriginKeyLookup.add_public_key(family, key)
        Logger.info("Load origin public key #{Base.encode16(key)} - #{family}")
      end)
    end)
  end

  def load_transaction(%Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{content: content},
        validation_stamp: %ValidationStamp{
          timestamp: timestamp
        }
      }) do
    {:ok, daily_nonce_public_key, network_pool_address} =
      NodeRenewal.decode_transaction_content(content)

    NetworkLookup.set_network_pool_address(network_pool_address)

    NetworkLookup.set_daily_nonce_public_key(
      daily_nonce_public_key,
      NodeRenewalScheduler.next_application_date(timestamp)
    )
  end

  def load_transaction(%Transaction{type: :node_rewards, address: address}) do
    NetworkLookup.set_network_pool_address(address)
  end

  def load_transaction(_), do: :ok

  defp get_origin_public_keys_from_tx_content(content) when is_binary(content) do
    [
      software: extract_origin_public_keys_from_family(@software_origin_key_regex, content),
      hardware: extract_origin_public_keys_from_family(@hardware_origin_key_regex, content),
      biometric: extract_origin_public_keys_from_family(@biometric_origin_key_regex, content)
    ]
  end

  defp extract_origin_public_keys_from_family(family_regex, origin_keys_string) do
    Regex.scan(family_regex, origin_keys_string)
    |> Enum.flat_map(& &1)
    |> List.first()
    |> handle_origin_family_match()
  end

  defp handle_origin_family_match(nil), do: []

  defp handle_origin_family_match(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.split(",")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn key ->
      key
      |> String.trim()
      |> Base.decode16!()
    end)
  end
end
