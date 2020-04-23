defmodule UnirisCore.SharedSecretsTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.SharedSecrets
  alias UnirisCore.Crypto

  test "new_node_shared_secrets_transaction/3 should create a new node shared secrets transaction" do
    aes_key = :crypto.strong_rand_bytes(32)

    %Transaction{
      type: :node_shared_secrets,
      data: %TransactionData{
        keys: %{
          authorized_keys: authorized_keys,
          daily_nonce_seed: encrypted_daily_nonce_seed,
          transaction_seed: encrypted_transaction_seed
        }
      }
    } =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.node_public_key()],
        "daily_nonce_seed",
        aes_key
      )

    assert Map.has_key?(authorized_keys, Crypto.node_public_key())
    encrypted_aes_key = Map.get(authorized_keys, Crypto.node_public_key())
    aes_key = Crypto.ec_decrypt_with_node_key!(encrypted_aes_key)
    Crypto.aes_decrypt!(encrypted_daily_nonce_seed, aes_key)
    Crypto.aes_decrypt!(encrypted_transaction_seed, aes_key)
  end
end
