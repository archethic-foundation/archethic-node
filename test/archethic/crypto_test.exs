defmodule CryptoTest do
  use ArchethicCase, async: false
  use ExUnitProperties

  alias Archethic.Crypto
  alias Archethic.Crypto.ID

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  import Mox

  doctest Crypto

  property "symmetric aes encryption and decryption" do
    check all(
            aes_key <- StreamData.binary(length: 32),
            data <- StreamData.binary(min_length: 1)
          ) do
      cipher = Crypto.aes_encrypt(data, aes_key)
      is_binary(cipher) and data == Crypto.aes_decrypt!(cipher, aes_key)
    end
  end

  property "symmetric EC encryption and decryption with ECDSA" do
    check all(
            seed <- StreamData.binary(length: 32),
            data <- StreamData.binary(min_length: 1)
          ) do
      {pub, pv} = Crypto.generate_deterministic_keypair(seed, :secp256r1)
      cipher = Crypto.ec_encrypt(data, pub)
      is_binary(cipher) and data == Crypto.ec_decrypt!(cipher, pv)
    end
  end

  property "symmetric EC encryption and decryption with Ed25519" do
    check all(
            seed <- StreamData.binary(length: 32),
            data <- StreamData.binary(min_length: 1)
          ) do
      {pub, pv} = Crypto.generate_deterministic_keypair(seed, :ed25519)
      cipher = Crypto.ec_encrypt(data, pub)
      is_binary(cipher) and data == Crypto.ec_decrypt!(cipher, pv)
    end
  end

  test "decrypt_and_set_storage_nonce/1 should decrypt storage nonce using node last key and and load storage nonce" do
    storage_nonce = :crypto.strong_rand_bytes(32)

    me = self()

    MockCrypto.SharedSecretsKeystore
    |> stub(:set_storage_nonce, fn nonce ->
      send(me, {:nonce, nonce})
      :ok
    end)

    assert :ok =
             Crypto.decrypt_and_set_storage_nonce(
               Crypto.ec_encrypt(storage_nonce, Crypto.last_node_public_key())
             )

    assert_receive {:nonce, ^storage_nonce}
  end

  test "encrypt_storage_nonce/1 should encrypt storage nonce using a public key" do
    {pub, pv} = Crypto.derive_keypair("seed", 0)
    :persistent_term.put(:storage_nonce, "nonce")

    assert "nonce" ==
             pub
             |> Crypto.encrypt_storage_nonce()
             |> Crypto.ec_decrypt!(pv)
  end

  describe "load_transaction/1" do
    test "should create a new next keypair when the node transaction is validated" do
      me = self()

      MockCrypto.NodeKeystore
      |> expect(:persist_next_keypair, fn ->
        send(me, :new_keypair)
        :ok
      end)

      tx = Transaction.new(:node, %TransactionData{})
      assert :ok = Crypto.load_transaction(tx)

      assert_receive :new_keypair
    end

    test "should update node shared secrets" do
      me = self()

      MockCrypto.SharedSecretsKeystore
      |> expect(:set_node_shared_secrets_key_index, fn _ ->
        send(me, :inc_node_shared_key_index)
        :ok
      end)

      tx = %Transaction{
        address: "@NodeSharedSecrets1",
        type: :node_shared_secrets,
        data: %TransactionData{ownerships: [%Ownership{secret: :crypto.strong_rand_bytes(32)}]},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert :ok = Crypto.load_transaction(tx)
      assert_receive :inc_node_shared_key_index
    end

    test "should decrypt and load node shared secrets seeds" do
      transaction_seed = :crypto.strong_rand_bytes(32)
      daily_nonce_seed = :crypto.strong_rand_bytes(32)
      network_seed = :crypto.strong_rand_bytes(32)

      secret_key = :crypto.strong_rand_bytes(32)

      me = self()

      MockCrypto.SharedSecretsKeystore
      |> stub(:unwrap_secrets, fn _, _, _ ->
        send(me, {:daily_nonce_seed, daily_nonce_seed})
        send(me, {:transaction_seed, transaction_seed})
        send(me, {:network_seed, network_seed})
        :ok
      end)

      enc_daily_nonce_seed = Crypto.aes_encrypt(daily_nonce_seed, secret_key)
      enc_transaction_seed = Crypto.aes_encrypt(transaction_seed, secret_key)
      enc_network_seed = Crypto.aes_encrypt(network_seed, secret_key)

      secret =
        <<enc_daily_nonce_seed::binary, enc_transaction_seed::binary, enc_network_seed::binary>>

      ownership = Ownership.new(secret, secret_key, [Crypto.last_node_public_key()])

      MockDB
      |> expect(:chain_size, fn _ -> 0 end)

      tx = %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :node_shared_secrets,
        data: %TransactionData{ownerships: [ownership]},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert :ok = Crypto.load_transaction(tx)

      assert_receive {:transaction_seed, ^transaction_seed}
      assert_receive {:daily_nonce_seed, ^daily_nonce_seed}
      assert_receive {:network_seed, ^network_seed}
    end
  end

  test "aggregate_signatures/1 should produce a valid signature" do
    {pub1, pv1} = Crypto.generate_deterministic_keypair("seed1", :bls)
    {pub2, pv2} = Crypto.generate_deterministic_keypair("seed2", :bls)
    sig1 = Crypto.sign("hello", pv1)
    sig2 = Crypto.sign("hello", pv2)
    aggregated_signature = Crypto.aggregate_signatures([sig1, sig2], [pub1, pub2])
    aggregated_public_key = Crypto.aggregate_mining_public_keys([pub1, pub2])
    assert Crypto.verify?(aggregated_signature, "hello", aggregated_public_key)
  end
end
