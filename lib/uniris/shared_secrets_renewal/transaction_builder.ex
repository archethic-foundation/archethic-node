defmodule Uniris.SharedSecretsRenewal.TransactionBuilder do
  @moduledoc false

  alias Uniris.Crypto

  alias Uniris.Transaction
  alias Uniris.TransactionData
  alias Uniris.TransactionData.Keys

  @doc """
  Create a new transaction for node shared secrets renewal generating secret encrypted using the aes key and daily nonce seed
  for the authorized nodes public keys
  """
  @spec new_node_shared_secrets_transaction(
          daily_nonce_seed :: binary(),
          aes_key :: binary(),
          authorized_nodes_public_keys :: list(binary())
        ) :: Transaction.t()
  def new_node_shared_secrets_transaction(daily_nonce_seed, aes_key, authorized_node_public_keys)
      when is_binary(daily_nonce_seed) and is_binary(aes_key) and
             is_list(authorized_node_public_keys) do
    {daily_nonce_public_key, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    secret =
      Crypto.aes_encrypt(daily_nonce_seed, aes_key) <>
        Crypto.encrypt_node_shared_secrets_transaction_seed(aes_key)

    Transaction.new(
      :node_shared_secrets,
      %TransactionData{
        content: """
        daily_nonce_public_key: #{Base.encode16(daily_nonce_public_key)}
        """,
        keys: Keys.new(authorized_node_public_keys, aes_key, secret)
      }
    )
  end
end
