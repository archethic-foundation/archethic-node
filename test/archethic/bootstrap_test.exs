defmodule Archethic.BootstrapTest do
  use ArchethicCase

  alias Archethic.{
    Bootstrap,
    Crypto,
    P2P,
    P2P.BootstrappingSeeds,
    P2P.Node,
    Replication,
    SharedSecrets,
    SharedSecrets.NodeRenewalScheduler,
    TransactionChain,
    TransactionFactory
  }

  alias Archethic.P2P.Message.{
    GetTransactionChainLength,
    TransactionChainLength,
    BootstrappingNodes,
    EncryptedStorageNonce,
    GetBootstrappingNodes,
    GetLastTransactionAddress,
    GetStorageNonce,
    GetTransaction,
    GetTransactionChain,
    GetTransactionSummary,
    GetTransactionInputs,
    GetGenesisAddress,
    GenesisAddress,
    LastTransactionAddress,
    ListNodes,
    NewTransaction,
    NodeList,
    NotFound,
    NotifyEndOfNodeSync,
    TransactionList,
    TransactionInputList,
    TransactionSummaryMessage,
    Ok,
    GetGenesisAddress,
    NotFound
  }

  alias TransactionChain.{
    Transaction,
    TransactionSummary,
    Transaction.ValidationStamp,
    Transaction.ValidationStamp.LedgerOperations
  }

  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer
  alias Archethic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Archethic.Reward.MemTables.RewardTokens, as: RewardMemTable
  alias Archethic.Reward.MemTablesLoader, as: RewardTableLoader

  import Mox

  setup do
    start_supervised!({BeaconSummaryTimer, interval: "0 0 * * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!({SelfRepairScheduler, interval: "0 * * * * * *"})
    start_supervised!(BootstrappingSeeds)
    start_supervised!({NodeRenewalScheduler, interval: "0 * * * * * *"})

    MockDB
    |> stub(:write_transaction, fn _, _ -> :ok end)

    MockDB
    |> stub(:list_transactions_by_type, fn :mint_rewards, [:address, :type] ->
      [
        %Transaction{
          address: "@RewardToken0",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken1",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken2",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken3",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        },
        %Transaction{
          address: "@RewardToken4",
          type: :mint_rewards,
          validation_stamp: %ValidationStamp{ledger_operations: %LedgerOperations{fee: 0}}
        }
      ]
    end)

    start_supervised!(RewardMemTable)
    start_supervised!(RewardTableLoader)

    :ok
  end

  describe "run/5" do
    setup do
      :persistent_term.put(:node_shared_secrets_gen_addr, nil)
    end

    test "should initialize the network when nothing is set before" do
      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address, timestamp: DateTime.utc_now()}}

        _, %GetTransactionInputs{}, _ ->
          {:ok, %TransactionInputList{inputs: []}}

        _, %GetTransactionChain{}, _ ->
          {:ok, %TransactionList{transactions: []}}

        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}

        _, %NotifyEndOfNodeSync{}, _ ->
          {:ok, %Ok{}}

        _, %GetTransactionChainLength{}, _ ->
          %TransactionChainLength{length: 1}

        _, %GetGenesisAddress{}, _ ->
          {:ok, %NotFound{}}
      end)

      {:ok, daily_nonce_agent} = Agent.start_link(fn -> %{} end)

      MockDB
      |> stub(:chain_size, fn _ -> 1 end)

      MockCrypto
      |> stub(:unwrap_secrets, fn encrypted_secrets, encrypted_secret_key, timestamp ->
        <<enc_daily_nonce_seed::binary-size(60), _enc_transaction_seed::binary-size(60),
          _enc_network_pool_seed::binary-size(60)>> = encrypted_secrets

        {:ok, aes_key} = Crypto.ec_decrypt_with_first_node_key(encrypted_secret_key)
        {:ok, daily_nonce_seed} = Crypto.aes_decrypt(enc_daily_nonce_seed, aes_key)
        daily_nonce_keypair = Crypto.generate_deterministic_keypair(daily_nonce_seed)

        Agent.update(daily_nonce_agent, fn state ->
          Map.put(state, timestamp, daily_nonce_keypair)
        end)
      end)
      |> stub(:sign_with_daily_nonce_key, fn data, timestamp ->
        {_pub, pv} =
          Agent.get(daily_nonce_agent, fn state ->
            state
            |> Enum.sort_by(&elem(&1, 0), {:desc, DateTime})
            |> Enum.filter(&(DateTime.diff(elem(&1, 0), timestamp) <= 0))
            |> List.first()
            |> elem(1)
          end)

        Crypto.sign(data, pv)
      end)

      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: Crypto.first_node_public_key(),
          last_public_key: Crypto.last_node_public_key()
        }
      ]

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "0000610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      assert [%Node{ip: {127, 0, 0, 1}, authorized?: true, transport: :tcp} | _] =
               P2P.list_nodes()

      assert 1 == Crypto.number_of_node_shared_secrets_keys()

      assert 2 == SharedSecrets.list_origin_public_keys() |> Enum.count()
    end
  end

  describe "run/5 with an initialized network" do
    setup do
      nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key:
            <<0, 0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138, 166,
              24, 164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
          first_public_key:
            <<0, 0, 220, 205, 110, 4, 194, 222, 148, 194, 164, 97, 116, 158, 146, 181, 138, 166,
              24, 164, 86, 69, 130, 245, 19, 203, 19, 163, 2, 19, 160, 205, 9, 200>>,
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          enrollment_date: DateTime.utc_now(),
          reward_address:
            <<0, 0, 245, 206, 118, 231, 188, 183, 250, 138, 217, 84, 176, 169, 37, 230, 8, 17,
              147, 90, 187, 118, 27, 143, 165, 86, 151, 130, 250, 231, 32, 155, 183, 79>>
        },
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          last_public_key:
            <<0, 0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249, 111,
              74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
          first_public_key:
            <<0, 0, 186, 140, 57, 71, 50, 47, 229, 252, 24, 60, 6, 188, 83, 193, 145, 249, 111,
              74, 30, 113, 111, 191, 242, 155, 199, 104, 181, 21, 95, 208, 108, 146>>,
          geo_patch: "BBB",
          network_patch: "BBB",
          authorized?: true,
          authorization_date: DateTime.utc_now(),
          available?: true,
          enrollment_date: DateTime.utc_now(),
          reward_address:
            <<0, 0, 122, 59, 37, 225, 0, 2, 24, 151, 241, 79, 158, 121, 16, 7, 168, 150, 94, 164,
              74, 201, 0, 202, 242, 185, 133, 85, 186, 73, 199, 223, 143>>
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        _, %GetBootstrappingNodes{}, _ ->
          {:ok,
           %BootstrappingNodes{
             new_seeds: [
               Enum.at(nodes, 0)
             ],
             closest_nodes: [
               Enum.at(nodes, 1)
             ]
           }}

        _, %NewTransaction{transaction: tx}, _ ->
          stamp = %ValidationStamp{
            timestamp: DateTime.utc_now(),
            proof_of_work: "",
            proof_of_integrity: "",
            ledger_operations: %LedgerOperations{}
          }

          validated_tx = %{tx | validation_stamp: stamp}
          :ok = TransactionChain.write_transaction(validated_tx)
          :ok = Replication.ingest_transaction(validated_tx, false)

          {:ok, %Ok{}}

        _, %GetStorageNonce{}, _ ->
          {:ok,
           %EncryptedStorageNonce{
             digest:
               Crypto.ec_encrypt(:crypto.strong_rand_bytes(32), Crypto.last_node_public_key())
           }}

        _, %ListNodes{}, _ ->
          {:ok, %NodeList{nodes: nodes}}

        _, %NotifyEndOfNodeSync{}, _ ->
          {:ok, %Ok{}}

        # _, %GetTransaction{address: address}, _ ->
        #   {:ok,
        #    %Transaction{
        #      address: address,
        #      validation_stamp: %ValidationStamp{},
        #      cross_validation_stamps: [%{}]
        #    }}
        _, %GetTransaction{}, _ ->
          {:ok, %NotFound{}}

        _, %GetTransactionSummary{address: address}, _ ->
          {:ok,
           %TransactionSummaryMessage{
             transaction_summary: %TransactionSummary{
               address: address
             }
           }}

        _, %GetTransactionChainLength{}, _ ->
          {:ok, %TransactionChainLength{length: 0}}
      end)

      :ok
    end

    test "should add a new node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          network_patch: "AAA",
          reward_address:
            <<0, 122, 59, 37, 225, 0, 2, 24, 151, 241, 79, 158, 121, 16, 7, 168, 150, 94, 164, 74,
              201, 0, 202, 242, 185, 133, 85, 186, 73, 199, 223, 143>>
        }
      ]

      Enum.each(seeds, &P2P.add_and_connect_node/1)

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "0000610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      assert Enum.any?(P2P.list_nodes(), &(&1.first_public_key == Crypto.first_node_public_key()))
    end

    test "should update a node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          http_port: 4000,
          first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          network_patch: "AAA",
          reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
        }
      ]

      Enum.each(seeds, &P2P.add_and_connect_node/1)

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "0000610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      %Node{
        ip: {127, 0, 0, 1},
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        transport: :tcp
      } = P2P.get_node_info()

      assert first_public_key == Crypto.first_node_public_key()
      assert last_public_key == Crypto.first_node_public_key()

      MockDB
      |> stub(:get_first_public_key, fn _ -> first_public_key end)

      MockGeoIP
      |> stub(:get_coordinates, fn {200, 50, 20, 10} -> {0.0, 0.0} end)

      assert :ok =
               Bootstrap.run(
                 {200, 50, 20, 10},
                 3000,
                 4000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "0000610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      %Node{
        ip: {200, 50, 20, 10},
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        transport: :tcp
      } = P2P.get_node_info()

      assert first_public_key == Crypto.first_node_public_key()
      assert last_public_key == Crypto.last_node_public_key()
    end

    test "should not bootstrap when you are the first node and you restart the node" do
      seeds = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          http_port: 4000,
          first_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          last_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          network_patch: "AAA",
          reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
        }
      ]

      Enum.each(seeds, &P2P.add_and_connect_node/1)

      assert :ok =
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "0000610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      assert %Node{ip: {127, 0, 0, 1}} = P2P.get_node_info!(Crypto.first_node_public_key())

      Process.sleep(200)

      assert :ok ==
               Bootstrap.run(
                 {127, 0, 0, 1},
                 3000,
                 4000,
                 :tcp,
                 seeds,
                 DateTime.utc_now(),
                 "0000610F69B6C5C3449659C99F22956E5F37AA6B90B473585216CF4931DAF7A0AB45"
                 |> Base.decode16!()
               )

      Process.sleep(100)
    end
  end

  describe "resync_network_chain/2 nss_chain" do
    setup do
      p2p_context()

      curr_time = DateTime.utc_now()

      txn0 =
        TransactionFactory.create_network_tx(:node_shared_secrets,
          index: 0,
          timestamp: curr_time |> DateTime.add(-14_400, :second),
          prev_txn: []
        )

      txn1 =
        TransactionFactory.create_network_tx(:node_shared_secrets,
          index: 1,
          timestamp: curr_time |> DateTime.add(-14_400, :second),
          prev_txn: [txn0]
        )

      txn2 =
        TransactionFactory.create_network_tx(:node_shared_secrets,
          index: 2,
          timestamp: curr_time |> DateTime.add(-7_200, :second),
          prev_txn: [txn1]
        )

      txn3 =
        TransactionFactory.create_network_tx(:node_shared_secrets,
          index: 3,
          timestamp: curr_time |> DateTime.add(-3_600, :second),
          prev_txn: [txn2]
        )

      txn4 =
        TransactionFactory.create_network_tx(:node_shared_secrets,
          index: 4,
          timestamp: curr_time,
          prev_txn: [txn3]
        )

      :persistent_term.put(:node_shared_secrets_gen_addr, txn0.address)
      %{txn0: txn0, txn1: txn1, txn2: txn2, txn3: txn3, txn4: txn4}
    end

    test "Should return :ok when Genesis Address are not loaded", _nss_chain do
      # first time boot no txns exits yet
      :persistent_term.put(:node_shared_secrets_gen_addr, nil)

      assert :ok =
               Bootstrap.do_resync_network_chain(
                 :node_shared_secrets,
                 _nodes = P2P.authorized_and_available_nodes()
               )
    end

    test "Should return :ok when last address match (locally and remotely)", nss_chain do
      # node restart but within renewal interval
      me = self()
      addr0 = nss_chain.txn0.address

      MockDB
      |> stub(:get_last_chain_address, fn ^addr0 ->
        send(me, :local_last_addr_request)
        {nss_chain.txn4.address, DateTime.utc_now()}
      end)

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: ^addr0}, _ ->
          send(me, :remote_last_addr_request)
          {:ok, %LastTransactionAddress{address: nss_chain.txn4.address}}

        _, %GetTransaction{}, _ ->
          send(me, :fetch_last_txn)
      end)

      assert :ok =
               Bootstrap.do_resync_network_chain(
                 :node_shared_secrets,
                 _nodes = P2P.authorized_and_available_nodes()
               )

      assert_receive(:local_last_addr_request)
      assert_receive(:remote_last_addr_request)
      refute_receive(:fetch_last_txn)
    end

    test "should Retrieve and Store Network tx's, when last tx's not available", nss_chain do
      # scenario nss chain
      # addr0 -> addr1 -> addr2 -> addr3  -> addr4
      # node1 =>  addr0 -> addr1 -> addr2
      # node2 => addr0 -> addr1 -> addr2 -> addr3  -> addr4
      addr0 = nss_chain.txn0.address
      addr1 = nss_chain.txn1.address
      addr2 = nss_chain.txn2.address
      addr3 = nss_chain.txn3.address
      addr4 = nss_chain.txn4.address

      me = self()

      now = DateTime.utc_now()

      MockDB
      |> stub(:list_chain_addresses, fn
        ^addr0 -> [{addr1, now}, {addr2, now}, {addr3, now}, {addr4, now}]
      end)
      |> stub(:transaction_exists?, fn
        ^addr4, _ -> false
        ^addr3, _ -> false
        ^addr2, _ -> true
        ^addr1, _ -> true
      end)
      |> expect(:get_transaction, fn ^addr3, _, _ ->
        {:error, :transaction_not_exists}
      end)
      |> stub(:write_transaction, fn tx, _ ->
        # to know this fx executed or not we use send
        send(me, {:write_transaction, tx.address})
        :ok
      end)

      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{address: ^addr0}, _ ->
          {:ok, %LastTransactionAddress{address: addr4}}

        _, %GetTransaction{address: ^addr4}, _ ->
          {:ok, nss_chain.txn4}

        _, %GetTransaction{address: ^addr3}, _ ->
          {:ok, nss_chain.txn3}

        _, %GetTransactionInputs{address: ^addr3}, _ ->
          {:ok, %TransactionInputList{inputs: []}}

        _, %GetGenesisAddress{address: ^addr3}, _ ->
          {:ok, %GenesisAddress{address: addr0}}

        _, %GetTransactionChain{address: ^addr3, paging_state: ^addr2}, _ ->
          {:ok,
           %TransactionList{
             transactions: [nss_chain.txn3, nss_chain.txn4],
             more?: false,
             paging_state: nil
           }}
      end)

      assert :ok =
               Bootstrap.do_resync_network_chain(
                 :node_shared_secrets,
                 _nodes = P2P.authorized_and_available_nodes()
               )

      # flow
      # get_gen_addr(:pers_term) -> resolve_last_address ->   get_last_address
      #                                                         |
      # validate_and_store_transaction_chain <-   fetch_transaction_remotely
      #    |
      # transaction_exists? -> fetch_context(tx) -> get_last_txn (db then -> remote check)
      #                                                                 |
      # transaction_exists?(prev_txn\tx3) <- stream_previous_chain <- fetch_inputs_remotely
      #    |
      # stream_transaction_chain(addr3/prev-tx) -> fetch_genesis_address_remotely ->
      #                                                                 |
      # &TransactionChain.write/1 <- stream_remotely(addr3,addr2) <- get_last_address(locally)
      #    |
      #   write_transaction(tx4) -> ingest txn4
      assert_receive({:write_transaction, ^addr3})
      assert_receive({:write_transaction, ^addr4})
    end

    defp p2p_context() do
      pb_key3 = Crypto.derive_keypair("key33", 0) |> elem(0)

      SharedSecrets.add_origin_public_key(:software, Crypto.first_node_public_key())

      coordinator_node = %Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        authorization_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        geo_patch: "AAA",
        network_patch: "AAA",
        enrollment_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
        reward_address: Crypto.derive_address(Crypto.last_node_public_key())
      }

      storage_nodes = [
        %Node{
          ip: {127, 0, 0, 1},
          port: 3000,
          first_public_key: pb_key3,
          last_public_key: pb_key3,
          available?: true,
          authorized?: true,
          geo_patch: "BBB",
          network_patch: "BBB",
          authorization_date: DateTime.add(DateTime.utc_now(), -86_400, :second),
          reward_address: Crypto.derive_address(pb_key3),
          enrollment_date: DateTime.add(DateTime.utc_now(), -86_400, :second)
        }
      ]

      Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

      # P2P.add_and_connect_node(welcome_node)
      P2P.add_and_connect_node(coordinator_node)
    end
  end
end
