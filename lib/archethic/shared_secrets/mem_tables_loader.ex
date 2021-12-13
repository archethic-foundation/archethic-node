defmodule ArchEthic.SharedSecrets.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias ArchEthic.Crypto

  alias ArchEthic.SharedSecrets.MemTables.NetworkLookup
  alias ArchEthic.SharedSecrets.MemTables.OriginKeyLookup
  alias ArchEthic.SharedSecrets.NodeRenewal
  alias ArchEthic.SharedSecrets.NodeRenewalScheduler

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    TransactionChain.list_transactions_by_type(:origin_shared_secrets, [
      :address,
      :type,
      data: [:content]
    ])
    |> Stream.concat(
      TransactionChain.list_transactions_by_type(:node, [:address, :type, :previous_public_key])
    )
    |> Stream.concat(
      TransactionChain.list_transactions_by_type(:node_shared_secrets, [
        :address,
        :type,
        data: [:content],
        validation_stamp: [:timestamp]
      ])
    )
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the transaction into the memory table
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        address: address,
        type: :node,
        previous_public_key: previous_public_key
      }) do
    first_public_key = TransactionChain.get_first_public_key(previous_public_key)

    unless OriginKeyLookup.has_public_key?(first_public_key) do
      <<_::8, origin_id::8, _::binary>> = previous_public_key

      family =
        case Crypto.key_origin(origin_id) do
          :software ->
            :software

          :tpm ->
            :hardware
        end

      :ok = OriginKeyLookup.add_public_key(family, previous_public_key)

      Logger.info("Load origin public key #{Base.encode16(previous_public_key)} - #{family}",
        transaction_address: Base.encode16(address),
        transaction_type: :node
      )
    end

    :ok
  end

  def load_transaction(%Transaction{
        address: address,
        type: :origin_shared_secrets,
        data: %TransactionData{content: content}
      }) do
    content
    |> get_origin_public_keys(%{software: [], hardware: []})
    |> Enum.each(fn {family, keys} ->
      Enum.each(keys, fn key ->
        :ok = OriginKeyLookup.add_public_key(family, key)

        Logger.info("Load origin public key #{Base.encode16(key)} - #{family}",
          transaction_address: Base.encode16(address),
          transaction_type: :origin_shared_secrets
        )
      end)
    end)
  end

  def load_transaction(%Transaction{
        address: address,
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

    Logger.info("Load daily nonce public key: #{Base.encode16(daily_nonce_public_key)}",
      transaction_address: Base.encode16(address),
      transaction_type: :node_shared_secrets
    )
  end

  def load_transaction(%Transaction{type: :node_rewards, address: address}) do
    NetworkLookup.set_network_pool_address(address)
  end

  def load_transaction(_), do: :ok

  defp get_origin_public_keys(<<>>, acc), do: acc

  defp get_origin_public_keys(<<curve_id::8, origin_id::8, rest::binary>>, acc) do
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), rest::binary>> = rest

    family =
      case Crypto.key_origin(origin_id) do
        :software ->
          :software

        :tpm ->
          :hardware
      end

    get_origin_public_keys(
      rest,
      Map.update!(acc, family, &[<<curve_id::8, origin_id::8, key::binary>> | &1])
    )
  end
end
