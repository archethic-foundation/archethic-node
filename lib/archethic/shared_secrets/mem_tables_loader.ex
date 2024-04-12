defmodule Archethic.SharedSecrets.MemTablesLoader do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Crypto
  alias Archethic.Utils

  alias Archethic.P2P.Node

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.SharedSecrets.MemTables.OriginKeyLookup
  alias Archethic.SharedSecrets.NodeRenewal
  alias Archethic.SharedSecrets.NodeRenewalScheduler

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    TransactionChain.list_transactions_by_type(:origin, [
      :address,
      :type,
      data: [:content]
    ])
    |> Stream.concat(
      TransactionChain.list_transactions_by_type(:node, [:address, :type, data: [:content]])
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
        data: %TransactionData{
          content: content
        }
      }) do
    {:ok, _ip, _p2p_port, _http_port, _transport, _reward_address, origin_public_key, _cert} =
      Node.decode_transaction_content(content)

    <<_::8, origin_id::8, _::binary>> = origin_public_key

    family =
      case Crypto.key_origin(origin_id) do
        :software ->
          :software

        :tpm ->
          :hardware

        :on_chain_wallet ->
          :software
      end

    :ok = OriginKeyLookup.add_public_key(family, origin_public_key)

    Logger.info("Load origin public key #{Base.encode16(origin_public_key)} - #{family}",
      transaction_address: Base.encode16(address),
      transaction_type: :node
    )

    :ok
  end

  def load_transaction(%Transaction{
        address: address,
        type: :origin,
        data: %TransactionData{content: content}
      }) do
    {origin_public_key, _rest} = Utils.deserialize_public_key(content)

    <<_curve_id::8, origin_id::8, _rest::binary>> = origin_public_key

    family = SharedSecrets.get_origin_family_from_origin_id(origin_id)

    OriginKeyLookup.add_public_key(family, origin_public_key)

    Logger.info("Load origin public key #{Base.encode16(origin_public_key)} - #{family}",
      transaction_address: Base.encode16(address),
      transaction_type: :origin
    )
  end

  def load_transaction(%Transaction{
        address: address,
        type: :node_shared_secrets,
        data: %TransactionData{content: content},
        validation_stamp: %ValidationStamp{
          timestamp: timestamp
        }
      }) do
    {:ok, daily_nonce_public_key} = NodeRenewal.decode_transaction_content(content)

    NetworkLookup.set_daily_nonce_public_key(
      daily_nonce_public_key,
      NodeRenewalScheduler.next_application_date(timestamp)
    )

    Logger.info("Load daily nonce public key: #{Base.encode16(daily_nonce_public_key)}",
      transaction_address: Base.encode16(address),
      transaction_type: :node_shared_secrets
    )
  end

  def load_transaction(_), do: :ok
end
