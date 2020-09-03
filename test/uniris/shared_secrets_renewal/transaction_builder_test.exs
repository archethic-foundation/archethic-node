defmodule Uniris.SharedSecretsRenewal.TransactionBuilderTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.SharedSecretsRenewal.TransactionBuilder

  alias Uniris.Transaction
  alias Uniris.TransactionData
  alias Uniris.TransactionData.Keys

  test "new_node_shared_secrets_transaction/3 should create a new node shared secrets transaction" do
    aes_key = :crypto.strong_rand_bytes(32)

    %Transaction{
      type: :node_shared_secrets,
      data: %TransactionData{
        keys: %Keys{
          authorized_keys: authorized_keys,
          secret: _
        }
      }
    } =
      TransactionBuilder.new_node_shared_secrets_transaction(
        "daily_nonce_seed",
        aes_key,
        [Crypto.node_public_key()]
      )

    assert Map.has_key?(authorized_keys, Crypto.node_public_key())
  end
end
