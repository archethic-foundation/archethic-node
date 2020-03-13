defmodule UnirisSharedSecrets.DefaultImplTest do
  use ExUnit.Case

  alias UnirisCrypto, as: Crypto
  alias UnirisSharedSecrets.DefaultImpl, as: SharedSecrets
  alias UnirisChain.Transaction
  alias UnirisP2P.Node

  import Mox

  setup :verify_on_exit!

  test "new_shared_secrets_transaction/1 should generate a transaction for node shared secrets keys" do
    pub = Crypto.node_public_key()

    MockP2P
    |> expect(:list_nodes, fn ->
      [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: pub,
          last_public_key: pub
        }
      ]
    end)

    MockSharedSecrets
    |> stub(:add_origin_public_key, fn _, _ -> :ok end)

    shared_secret_seed = :crypto.strong_rand_bytes(32)

    %Transaction{
      data: %{
        content: content,
        keys: %{
          secret: cipher,
          authorized_keys: keys
        }
      }
    } = SharedSecrets.new_shared_secrets_transaction(shared_secret_seed)

    enc_aes = Map.get(keys, pub)
    aes_key = Crypto.ec_decrypt_with_node_key!(enc_aes)

    %{
      daily_nonce_seed: daily_nonce_seed,
      storage_nonce_seed: storage_nonce_seed,
      origin_keys_seeds: origin_keys_seeds
    } = Crypto.aes_decrypt!(cipher, aes_key)

    {daily_nonce_public_key, _} = Crypto.generate_deterministic_keypair(daily_nonce_seed)

    {storage_nonce_public_key, _} = Crypto.generate_deterministic_keypair(storage_nonce_seed)

    origin_public_keys =
      Enum.map(origin_keys_seeds, fn seed ->
        {pub, _} = Crypto.generate_deterministic_keypair(seed)
        Base.encode16(pub)
      end)
      |> Enum.join(",")

    assert String.contains?(
             content,
             """
             daily_nonce_public: #{Base.encode16(daily_nonce_public_key)}
             storage_nonce_public: #{Base.encode16(storage_nonce_public_key)}
             origin_public_keys: #{origin_public_keys}
             """
           )
  end
end
