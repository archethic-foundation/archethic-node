defmodule Uniris.SharedSecrets.NodeRenewal do
  @moduledoc """
  Represent the new node shared secrets renewal combining authorized nodes and secrets
  """
  defstruct [:authorized_nodes, :authorization_date, :secret]

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.SelfRepair

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Keys

  @type t :: %__MODULE__{
          authorized_nodes: list(Crypto.key()),
          secret: binary(),
          authorization_date: DateTime.t()
        }

  @doc """
  Determine if the local node is the initiator of the node renewal
  """
  @spec initiator?() :: boolean()
  def initiator? do
    %Node{first_public_key: initiator_key} =
      next_address()
      |> Replication.chain_storage_nodes()
      |> List.first()

    initiator_key == Crypto.first_node_public_key()
  end

  defp next_address do
    key_index = Crypto.number_of_node_shared_secrets_keys()
    next_public_key = Crypto.node_shared_secrets_public_key(key_index + 1)
    Crypto.hash(next_public_key)
  end

  @doc """
  List the next authorized node public keys
  """
  @spec next_authorized_node_public_keys() :: list(Crypto.key())
  def next_authorized_node_public_keys do
    SelfRepair.get_latest_tps()
    |> Election.next_authorized_nodes(P2P.available_nodes())
    |> Enum.map(& &1.last_public_key)
  end

  @doc """
  Create a new transaction for node shared secrets renewal generating secret encrypted using the secret key
  for the authorized nodes public keys

  The secret keys is encrypted with the list of authorized nodes public keys

  The secret is segmented by 180 bytes ( multiple encryption of 32 bytes )
  |------------------------|------------------------------|------------------------------|
  | Daily Nonce (60 bytes) | Transaction Seed (60 bytes)  |   Network seed (60 bytes)    |
  |------------------------|------------------------------|------------------------------|
  """
  @spec new_node_shared_secrets_transaction(
          authorized_nodes_public_keys :: list(Crypto.key()),
          daily_nonce_seed :: binary(),
          secret_key :: binary()
        ) :: Transaction.t()
  def new_node_shared_secrets_transaction(
        authorized_node_public_keys,
        daily_nonce_seed,
        secret_key
      )
      when is_binary(daily_nonce_seed) and is_binary(secret_key) and
             is_list(authorized_node_public_keys) do
    {daily_nonce_public_key, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    {encrypted_transaction_seed, encrypted_network_pool_seed} = Crypto.wrap_secrets(secret_key)
    encrypted_daily_nonce_seed = Crypto.aes_encrypt(daily_nonce_seed, secret_key)

    secret =
      <<encrypted_daily_nonce_seed::binary, encrypted_transaction_seed::binary,
        encrypted_network_pool_seed::binary>>

    network_pool_address =
      Crypto.number_of_network_pool_keys()
      |> Crypto.network_pool_public_key()
      |> Crypto.hash()

    Transaction.new(
      :node_shared_secrets,
      %TransactionData{
        code: """
        condition inherit: [
          # We need to ensure the type stays consistent
          # So we can apply specific rules during the transaction validation
          type: node_shared_secrets,

          # We discard the content, authorized_key and secret verification
          content: true,
          authorized_keys: true,
          secret: true
        ]
        """,
        content: """
        daily nonce public key: #{Base.encode16(daily_nonce_public_key)}
        network pool address: #{Base.encode16(network_pool_address)}
        """,
        keys: Keys.new(authorized_node_public_keys, secret_key, secret)
      }
    )
  end

  @doc """
  Decode the transaction content from the node renewal transaction
  """
  @spec decode_transaction_content(binary()) :: {:ok, binary(), binary()} | :error
  def decode_transaction_content(content) when is_binary(content) do
    pattern =
      ~r/daily nonce public key: ([0-9a-fA-F]{66,130})\nnetwork pool address: ([0-9a-fA-F]{66,130})/m

    with [[daily_nonce_public_key, network_pool_address]] <-
           Regex.scan(pattern, content, capture: :all_but_first),
         {:ok, daily_nonce_public_key} <- Base.decode16(daily_nonce_public_key, case: :mixed),
         {:ok, network_pool_address} <- Base.decode16(network_pool_address, case: :mixed) do
      {:ok, daily_nonce_public_key, network_pool_address}
    else
      _ ->
        :error
    end
  end
end
