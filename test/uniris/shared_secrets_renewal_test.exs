defmodule Uniris.SharedSecretsRenewalTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.StartMining

  alias Uniris.P2P.Node

  alias Uniris.SharedSecretsRenewal
  alias Uniris.Storage.Memory.NetworkLedger

  alias Uniris.Transaction
  alias Uniris.TransactionData

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    %{pid: start_supervised!({SharedSecretsRenewal, interval: "* * * * * *", trigger_offset: 1})}
  end

  test "should accept :start_node_renewal message to create a new transaction with new authorized nodes",
       %{pid: pid} do
    me = self()

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        %StartMining{transaction: tx} ->
          send(me, tx)
          {:ok, %Ok{}}
      end
    end)

    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: pub,
      first_public_key: pub,
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true
    })

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true
    })

    send(pid, :start_node_renewal)

    receive do
      %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{keys: %{authorized_keys: auth_keys}}
      } ->
        assert Map.has_key?(auth_keys, Crypto.node_public_key())
    end
  end

  @tag time_based: true
  test "receive every minute the message to create new node shared secrets" do
    me = self()

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        %StartMining{transaction: tx} ->
          send(me, tx)
          {:ok, %Ok{}}
      end
    end)

    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: pub,
      first_public_key: pub,
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true
    })

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true
    })

    receive do
      %Transaction{
        type: :node_shared_secrets,
        data: %TransactionData{keys: %{authorized_keys: auth_keys}},
        timestamp: timestamp
      } ->
        assert timestamp.second == 59
        assert Map.has_key?(auth_keys, Crypto.node_public_key())
    end
  end

  @tag time_based: true
  test "schedule_node_renewal_application/3 should trigger the renewal of keys in the interval" do
    {pub, _} = Crypto.generate_deterministic_keypair("seed")

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: pub,
      first_public_key: pub,
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true
    })

    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(),
      first_public_key: Crypto.node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true
    })

    daily_nonce_seed = :crypto.strong_rand_bytes(32)
    aes_key = :crypto.strong_rand_bytes(32)
    encrypted_aes_key = Crypto.ec_encrypt(aes_key, Crypto.node_public_key())

    :crypto.strong_rand_bytes(32)
    |> Crypto.aes_encrypt(aes_key)
    |> Crypto.decrypt_and_set_node_shared_secrets_transaction_seed(encrypted_aes_key)

    me = self()

    MockCrypto
    |> stub(:encrypt_node_shared_secrets_transaction_seed, fn key ->
      Crypto.aes_encrypt(:crypto.strong_rand_bytes(32), key)
    end)
    |> stub(:decrypt_and_set_daily_nonce_seed, fn _, _ ->
      send(me, :daily_nonce_seed_set)
    end)

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        %StartMining{} ->
          {:ok, %Ok{}}
      end
    end)

    secret =
      Crypto.aes_encrypt(daily_nonce_seed, aes_key) <>
        Crypto.encrypt_node_shared_secrets_transaction_seed(aes_key)

    assert :ok =
             SharedSecretsRenewal.schedule_node_renewal_application(
               [
                 Crypto.node_public_key(),
                 pub
               ],
               encrypted_aes_key,
               secret,
               DateTime.utc_now()
             )

    receive do
      :daily_nonce_seed_set ->
        assert [
                 Crypto.node_public_key(),
                 pub
               ] == NetworkLedger.list_authorized_nodes() |> Enum.map(& &1.first_public_key)
    end
  end
end
