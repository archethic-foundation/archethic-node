defmodule Archethic.SelfRepair.Notifier.ImplTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.{
    Crypto,
    P2P,
    P2P.Node,
    SharedSecrets,
    SelfRepair.Notifier.Impl,
    TransactionChain.TransactionInput,
    TransactionChain.VersionedTransactionInput
  }

  alias P2P.Message.{
    GetTransaction,
    FirstAddress,
    GetTransactionInputs,
    TransactionInputList,
    GetFirstAddress,
    GetTransactionChain,
    TransactionList
  }

  alias Impl, as: NotifierImpl
  doctest NotifierImpl

  @registry_name NotifierImpl.registry_name()
  import Mox

  describe "RegistryOperations" do
    setup do
      case Process.whereis(@registry_name) do
        nil ->
          start_supervised!({Registry, name: @registry_name, keys: :unique, partitions: 1})

        pid when is_pid(pid) ->
          :ok
      end

      :ok
    end

    test "Naive Ops" do
      me = self()
      key = "gen_addr"

      Registry.register(@registry_name, key, [])

      assert [{^me, _}] = Registry.lookup(@registry_name, key)

      Registry.unregister(@registry_name, key)

      assert [] = Registry.lookup(@registry_name, key)
    end

    test "repair_in_progress?()/1" do
      key = "random_key"
      refute NotifierImpl.repair_in_progress?(key)

      Registry.register(@registry_name, key, [])
      Registry.unregister(@registry_name, key)
      refute NotifierImpl.repair_in_progress?(key)
    end

    test "Registry Must be Cleaned up automatically" do
      key = "random_process"
      refute NotifierImpl.repair_in_progress?(key)

      pid =
        spawn(fn ->
          Registry.register(@registry_name, "random_process", [])

          receive do
            :exit ->
              nil
          end
        end)

      Process.sleep(100)
      assert NotifierImpl.repair_in_progress?(key)

      send(pid, :exit)
      Process.sleep(100)

      refute NotifierImpl.repair_in_progress?(key)
    end
  end

  describe "repair_chain/2" do
    setup do
      pb_key2 = Crypto.derive_keypair("key22_random", 0) |> elem(0)
      pb_key3 = Crypto.derive_keypair("key23_random", 0) |> elem(0)

      SharedSecrets.add_origin_public_key(:software, Crypto.first_node_public_key())

      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        authorization_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        geo_patch: "AAA",
        network_patch: "AAA",
        enrollment_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        reward_address: Crypto.derive_address(Crypto.last_node_public_key())
      })

      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: pb_key2,
        last_public_key: pb_key2,
        available?: true,
        authorized?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        authorization_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        reward_address: Crypto.derive_address(pb_key2),
        enrollment_date: DateTime.add(DateTime.utc_now(), -86_400, :second)
      }
      |> P2P.add_and_connect_node()

      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: pb_key3,
        last_public_key: pb_key3,
        available?: true,
        authorized?: true,
        geo_patch: "BBB",
        network_patch: "BBB",
        authorization_date: DateTime.add(DateTime.utc_now(), -86_400 * 2, :second),
        reward_address: Crypto.derive_address(pb_key3),
        enrollment_date: DateTime.add(DateTime.utc_now(), -86_400 * 2, :second)
      }
      |> P2P.add_and_connect_node()

      :ok
    end

    test " a" do
      %{txn0: txn0, txn1: txn1, txn2: txn2} = factory_built_chain()

      addr0 = txn0.address
      addr1 = txn1.address
      addr2 = txn2.address

      MockDB
      |> stub(
        :transaction_exists?,
        fn _ ->
          false
        end
      )

      MockClient
      |> stub(:send_message, fn
        _, %GetFirstAddress{address: _}, _ ->
          {:ok, %FirstAddress{address: addr0}}

        _, %GetTransaction{address: ^addr2}, _ ->
          {:ok, txn2}

        _, %GetTransactionInputs{}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "@Apoorv",
                   amount: 2_000_000_000,
                   spent?: false,
                   type: :UCO,
                   timestamp: ~U[2022-10-09 08:39:10.463Z],
                   reward?: false
                 },
                 protocol_version: 1
               }
             ]
           }}

        _, %GetTransaction{address: ^addr0}, _ ->
          {:ok, txn0}

        _, %GetTransaction{address: ^addr1}, _ ->
          {:ok, txn1}

        _, %GetTransactionChain{}, _ ->
          {:ok,
           %TransactionList{
             transactions: [txn0, txn1, txn2],
             paging_state: nil,
             more?: false
           }}
      end)

      {:ok, :continue} = NotifierImpl.repair_chain(txn2.address, txn0.address)
    end

    def factory_built_chain() do
      alias Archethic.TransactionFactory
      seed = "seed gta sa"
      time = DateTime.utc_now()
      timestamp2 = time |> DateTime.add(-5000)
      timestamp1 = time |> DateTime.add(-5000 * 2)
      timestamp0 = time |> DateTime.add(-5000 * 3)

      txn0 =
        TransactionFactory.create_valid_chain(
          [],
          seed: seed,
          index: 0,
          prev_txn: [],
          timestamp: timestamp0
        )

      txn1 =
        TransactionFactory.create_valid_chain([],
          seed: seed,
          index: 1,
          prev_txn: [txn0],
          timestamp: timestamp1
        )

      txn2 =
        TransactionFactory.create_valid_chain([],
          seed: seed,
          index: 2,
          prev_txn: [txn1],
          timestamp: timestamp2
        )

      %{txn0: txn0, txn1: txn1, txn2: txn2}
    end
  end
end
