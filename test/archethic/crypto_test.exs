defmodule CryptoTest do
  use ArchEthicCase, async: false
  use ExUnitProperties

  alias ArchEthic.Crypto
  alias ArchEthic.Crypto.ID

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys

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

  test "hash_with_storage_nonce/1 should hash a data using the storage nonce" do
    :persistent_term.put(:storage_nonce, "mynonce")
    assert Crypto.hash(["mynonce", "hello"]) == Crypto.hash_with_storage_nonce("hello")
  end

  test "decrypt_and_set_storage_nonce/1 should decrypt storage nonce using node last key and and load storage nonce" do
    storage_nonce = :crypto.strong_rand_bytes(32)

    assert :ok =
             Crypto.decrypt_and_set_storage_nonce(
               Crypto.ec_encrypt(storage_nonce, Crypto.last_node_public_key())
             )

    assert {:ok, _} = File.read(Crypto.storage_nonce_filepath())
    File.rm(Crypto.storage_nonce_filepath())
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

      MockCrypto
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

      MockCrypto
      |> expect(:set_node_shared_secrets_key_index, fn _ ->
        send(me, :inc_node_shared_key_index)
        :ok
      end)

      tx = %Transaction{
        address: "@NodeSharedSecrets1",
        type: :node_shared_secrets,
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert :ok = Crypto.load_transaction(tx)
      assert_received :inc_node_shared_key_index
    end

    test "should decrypt and load node shared secrets seeds" do
      transaction_seed = :crypto.strong_rand_bytes(32)
      daily_nonce_seed = :crypto.strong_rand_bytes(32)
      network_seed = :crypto.strong_rand_bytes(32)

      secret_key = :crypto.strong_rand_bytes(32)

      me = self()

      MockCrypto
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

      tx_keys = Keys.new([Crypto.last_node_public_key()], secret_key, secret)

      MockDB
      |> expect(:chain_size, fn _ -> 0 end)

      tx = %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :node_shared_secrets,
        data: %TransactionData{keys: tx_keys},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      assert :ok = Crypto.load_transaction(tx)

      assert_receive {:transaction_seed, ^transaction_seed}
      assert_receive {:daily_nonce_seed, ^daily_nonce_seed}
      assert_receive {:network_seed, ^network_seed}
    end
  end
end
