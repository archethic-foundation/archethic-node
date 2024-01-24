defmodule Archethic.SharedSecrets.NodeRenewal do
  @moduledoc """
  Represent the new node shared secrets renewal combining authorized nodes and secrets
  """
  defstruct [:authorized_nodes, :authorization_date, :secret]

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  alias Archethic.Utils

  @type t :: %__MODULE__{
          authorized_nodes: list(Crypto.key()),
          secret: binary(),
          authorization_date: DateTime.t()
        }

  @spec next_address(non_neg_integer()) :: binary()
  def next_address(key_index) do
    next_public_key = Crypto.node_shared_secrets_public_key(key_index + 1)
    Crypto.derive_address(next_public_key)
  end

  @doc """
  List the next authorized node public keys
  """
  @spec next_authorized_node_public_keys() :: list(Crypto.key())
  def next_authorized_node_public_keys do
    DB.get_latest_tps()
    |> Election.next_authorized_nodes(candidates(), P2P.authorized_nodes())
    |> Enum.map(& &1.first_public_key)
  end

  @doc """
  List all the new candidates for the node shared secret renewal
  """
  @spec candidates() :: list(Node.t())
  def candidates do
    previous_authorized_nodes = P2P.authorized_nodes()
    P2P.available_nodes() -- previous_authorized_nodes
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
          secret_key :: binary(),
          index :: non_neg_integer()
        ) :: Transaction.t()
  def new_node_shared_secrets_transaction(
        authorized_node_public_keys,
        daily_nonce_seed,
        secret_key,
        index
      )
      when is_binary(daily_nonce_seed) and is_binary(secret_key) and
             is_list(authorized_node_public_keys) and is_integer(index) and
             index >= 0 do
    {daily_nonce_public_key, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    {encrypted_transaction_seed, encrypted_network_pool_seed} = Crypto.wrap_secrets(secret_key)
    encrypted_daily_nonce_seed = Crypto.aes_encrypt(daily_nonce_seed, secret_key)

    secret =
      <<encrypted_daily_nonce_seed::binary, encrypted_transaction_seed::binary,
        encrypted_network_pool_seed::binary>>

    network_pool_address =
      Crypto.number_of_network_pool_keys()
      |> Crypto.network_pool_public_key()
      |> Crypto.derive_address()

    Transaction.new(
      :node_shared_secrets,
      %TransactionData{
        code:
          TransactionData.compress_code("""
          condition inherit: [
            # We need to ensure the type stays consistent
            # So we can apply specific rules during the transaction validation
            type: node_shared_secrets,

            # We discard the content, authorized_key and secret verification
            content: true,
            authorized_keys: true,
            secrets: true
          ]
          """),
        content: <<daily_nonce_public_key::binary, network_pool_address::binary>>,
        ownerships: [
          Ownership.new(secret, secret_key, authorized_node_public_keys)
        ]
      },
      index
    )
  end

  @doc """
  Decode the transaction content from the node renewal transaction
  """
  @spec decode_transaction_content(binary()) :: {:ok, binary(), binary()} | :error
  def decode_transaction_content(content) when is_binary(content) do
    with {daily_nonce_public_key, rest} <- Utils.deserialize_public_key(content),
         {network_pool_address, _rest} <- Utils.deserialize_address(rest) do
      {:ok, daily_nonce_public_key, network_pool_address}
    else
      _ ->
        :error
    end
  end
end
