defmodule Archethic.BootstrapTest do
  use ArchethicCase

  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.SummaryTimer, as: BeaconSummaryTimer

  alias Archethic.Bootstrap
  alias Archethic.Bootstrap.TransactionHandler

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.BootstrappingSeeds
  alias Archethic.P2P.Node

  alias Archethic.P2P.Message.{
    BootstrappingNodes,
    EncryptedStorageNonce,
    GetBootstrappingNodes,
    GetGenesisAddress,
    GetLastTransactionAddress,
    GetStorageNonce,
    GetTransaction,
    GetTransactionChain,
    GetTransactionChainLength,
    GetTransactionInputs,
    LastTransactionAddress,
    ListNodes,
    NodeList,
    NotFound,
    NotifyEndOfNodeSync,
    Ok,
    TransactionChainLength,
    TransactionInputList,
    TransactionList,
    GetCurrentReplicationAttestations,
    CurrentReplicationAttestations
  }

  alias Archethic.Replication

  alias Archethic.Reward.MemTables.RewardTokens, as: RewardMemTable

  alias Archethic.SelfRepair.Scheduler, as: SelfRepairScheduler

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  import Mox
  import Mock

  setup do
    start_supervised!({BeaconSummaryTimer, interval: "0 0 * * * * *"})
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    start_supervised!({SelfRepairScheduler, interval: "0 * * * * * *"})
    start_supervised!(BootstrappingSeeds)

    MockDB
    |> stub(:write_transaction, fn _, _ -> :ok end)
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
    |> stub(:list_io_transactions, fn _ -> [] end)

    MockCrypto.NodeKeystore
    |> stub(:set_node_key_index, fn _ -> :ok end)

    start_supervised!(RewardMemTable)

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

        _, %GetCurrentReplicationAttestations{}, _ ->
          {:ok,
           %CurrentReplicationAttestations{
             replication_attestations: []
           }}
      end)

      {:ok, daily_nonce_agent} = Agent.start_link(fn -> %{} end)

      MockDB
      |> stub(:chain_size, fn _ -> 1 end)

      MockCrypto.SharedSecretsKeystore
      |> stub(:unwrap_secrets, fn encrypted_secrets, encrypted_secret_key, timestamp ->
        <<enc_daily_nonce_seed::binary-size(60), _enc_transaction_seed::binary-size(60),
          _enc_reward_seed::binary-size(60)>> = encrypted_secrets

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
    setup_with_mocks([
      {TransactionHandler, [:passthrough],
       send_transaction: fn tx, _ ->
         stamp = %ValidationStamp{
           timestamp: DateTime.utc_now(),
           proof_of_work: "",
           proof_of_integrity: "",
           ledger_operations: %LedgerOperations{}
         }

         validated_tx = %{tx | validation_stamp: stamp}
         # This Replication is for the node that received the StartMining message
         # expecting the transaction has been validated and replicated by all other nodes
         :ok = TransactionChain.write_transaction(validated_tx)
         genesis_address = Transaction.previous_address(validated_tx)

         :ok =
           Replication.ingest_transaction(validated_tx, genesis_address,
             io_transaction?: false,
             self_repair?: false
           )

         {:ok, validated_tx}
       end},
      {Replication, [:passthrough],
       sync_transaction_chain: fn _tx, _genesis, _nodes ->
         # This replication is the one called by the starting node.
         # But we don't replicate here as we previously did in other mock
         :ok
       end}
    ]) do
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
             ],
             first_enrolled_node: Enum.at(nodes, 0)
           }}

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

      assert_called(Replication.sync_transaction_chain(:_, :_, :_))

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

      assert_called_exactly(Replication.sync_transaction_chain(:_, :_, :_), 2)
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

      assert_called_exactly(Replication.sync_transaction_chain(:_, :_, :_), 1)

      Process.sleep(100)
    end
  end
end
