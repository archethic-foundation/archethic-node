defmodule Archethic.Bootstrap.NetworkInitTest do
  use ArchethicCase

  alias Archethic.Account
  alias Archethic.Crypto

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot, as: BeaconSlot
  alias Archethic.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Archethic.BeaconChain.Subset, as: BeaconSubset
  alias Archethic.BeaconChain.SubsetRegistry, as: BeaconSubsetRegistry

  alias Archethic.Bootstrap.NetworkInit

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetFirstAddress
  alias Archethic.P2P.Message.FirstAddress
  alias Archethic.P2P.Message.NotFound

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.MemTables.NetworkLookup
  alias Archethic.SharedSecrets.NodeRenewalScheduler

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.TransactionFactory

  alias Archethic.P2P.Message.GetFirstAddress
  import Mox

  alias Archethic.Reward.MemTables.RewardTokens, as: RewardMemTable
  alias Archethic.Reward.MemTablesLoader, as: RewardTableLoader

  @genesis_origin_public_keys Application.compile_env!(
                                :archethic,
                                [NetworkInit, :genesis_origin_public_keys]
                              )

  setup do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
    start_supervised!({NodeRenewalScheduler, interval: "*/2 * * * * * *"})

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.add(DateTime.utc_now(), -1),
      authorization_date: DateTime.add(DateTime.utc_now(), -1),
      authorized?: true,
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    MockClient
    |> stub(:send_message, fn _, %GetLastTransactionAddress{address: address}, _ ->
      {:ok, %LastTransactionAddress{address: address}}
    end)

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

  test "create_storage_nonce/0 should initialize the nonce in the crypto keystore" do
    assert :ok = NetworkInit.create_storage_nonce()
  end

  test "self_validation/2 should return a validated transaction" do
    MockClient
    |> stub(:send_message, fn _, %GetFirstAddress{address: address}, _ ->
      address
    end)

    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{to: "@Alice2", amount: 500_000_000_000}
              ]
            }
          }
        },
        "seed",
        0
      )

    unspent_outputs = [%UnspentOutput{amount: 1_000_000_000_000, from: tx.address, type: :UCO}]
    tx = NetworkInit.self_validation(tx, unspent_outputs)

    tx_fee = tx.validation_stamp.ledger_operations.fee
    unspent_output = 1_000_000_000_000 - (tx_fee + 500_000_000_000)

    assert %Transaction{
             validation_stamp: %ValidationStamp{
               ledger_operations: %LedgerOperations{
                 fee: ^tx_fee,
                 transaction_movements: [
                   %TransactionMovement{to: "@Alice2", amount: 500_000_000_000, type: :UCO}
                 ],
                 unspent_outputs: [
                   %UnspentOutput{
                     amount: ^unspent_output,
                     from: _,
                     type: :UCO
                   }
                 ]
               }
             }
           } = tx
  end

  test "self_replication/1 should insert the transaction and add to the beacon chain" do
    inputs = [
      %TransactionInput{
        amount: 499_999_000_000,
        from: "genesis",
        type: :UCO,
        timestamp: DateTime.utc_now()
      }
    ]

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: []}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: inputs}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetFirstAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    tx =
      TransactionFactory.create_valid_transaction(
        inputs,
        type: :transfer
      )

    me = self()

    MockDB
    |> stub(:write_transaction, fn ^tx ->
      send(me, :write_transaction)
      :ok
    end)

    NetworkInit.self_replication(tx)

    assert_received :write_transaction

    subset = BeaconChain.subset_from_address(tx.address)
    [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)

    tx_address = tx.address

    %{
      current_slot: %BeaconSlot{
        transaction_attestations: [
          %ReplicationAttestation{
            transaction_summary: %TransactionSummary{address: ^tx_address}
          }
        ]
      }
    } = :sys.get_state(pid)
  end

  test "init_node_shared_secrets_chain/1 should create node shared secrets transaction chain, load daily nonce and authorize node" do
    start_supervised!({Archethic.SelfRepair.Scheduler, [interval: "0 0 0 * *"]})

    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: [], more?: false, paging_state: nil}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: []}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetFirstAddress{address: address}, _ ->
        {:ok, %FirstAddress{address: address}}
    end)

    me = self()

    MockDB
    |> expect(:write_transaction, fn tx ->
      send(me, {:transaction, tx})
      :ok
    end)

    MockCrypto
    |> stub(:unwrap_secrets, fn _, _, _ ->
      send(me, :set_daily_nonce)
      send(me, :set_transaction_seed)
      send(me, :set_network_pool)
      :ok
    end)
    |> stub(:sign_with_daily_nonce_key, fn data, _ ->
      pv =
        Application.get_env(:archethic, Archethic.Bootstrap.NetworkInit)
        |> Keyword.fetch!(:genesis_daily_nonce_seed)
        |> Crypto.generate_deterministic_keypair()
        |> elem(1)

      Crypto.sign(data, pv)
    end)

    NetworkInit.init_node_shared_secrets_chain()

    assert_receive {:transaction, %Transaction{type: :node_shared_secrets}}
    assert_receive :set_network_pool
    assert_receive :set_daily_nonce
    assert_receive :set_transaction_seed

    assert %Node{authorized?: true} = P2P.get_node_info()
  end

  test "init_genesis_wallets/1 should initialize genesis wallets" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: [], more?: false, paging_state: nil}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: []}}

      _, %GetLastTransactionAddress{address: address}, _ ->
        {:ok, %LastTransactionAddress{address: address}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetFirstAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      available?: true,
      enrollment_date: DateTime.utc_now(),
      network_patch: "AAA",
      authorization_date: DateTime.utc_now(),
      authorized?: true,
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    assert :ok = NetworkInit.init_genesis_wallets()

    genesis_pools = Application.get_env(:archethic, NetworkInit)[:genesis_pools]

    assert Enum.all?(genesis_pools, fn %{address: address, amount: amount} ->
             match?(%{uco: ^amount}, Account.get_balance(address))
           end)
  end

  test "init_network_reward_pool/1 should initialize genesis wallets" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: [], more?: false, paging_state: nil}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: []}}

      _, %GetLastTransactionAddress{address: address}, _ ->
        {:ok, %LastTransactionAddress{address: address}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetFirstAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    network_pool_seed = :crypto.strong_rand_bytes(32)

    {_, pv} = Crypto.generate_deterministic_keypair(network_pool_seed)

    {pub, _} = Crypto.derive_keypair(network_pool_seed, 1)

    NetworkLookup.set_network_pool_address(Crypto.derive_address(pub))

    MockCrypto
    |> expect(:sign_with_network_pool_key, fn data, _ ->
      Crypto.sign(data, pv)
    end)
    |> stub(:network_pool_public_key, fn index ->
      {pub, _} = Crypto.derive_keypair(network_pool_seed, index)
      pub
    end)

    assert :ok = NetworkInit.init_network_reward_pool()

    network_address = SharedSecrets.get_network_pool_address()
    key = {network_address, 0}

    assert %{token: %{^key => 3_340_000_000_000_000}} = Account.get_balance(network_address)
  end

  test "init_software_origin_shared_secrets_chain/1 should create first origin shared secret transaction" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransaction{}, _ ->
        {:ok, %NotFound{}}

      _, %GetTransactionChain{}, _ ->
        {:ok, %TransactionList{transactions: [], more?: false, paging_state: nil}}

      _, %GetTransactionInputs{}, _ ->
        {:ok, %TransactionInputList{inputs: []}}

      _, %GetLastTransactionAddress{address: address}, _ ->
        {:ok, %LastTransactionAddress{address: address}}

      _, %GetTransactionChainLength{}, _ ->
        %TransactionChainLength{length: 1}

      _, %GetFirstAddress{}, _ ->
        {:ok, %NotFound{}}
    end)

    me = self()

    MockDB
    |> expect(:write_transaction, fn tx ->
      send(me, {:transaction, tx})
      :ok
    end)

    P2P.add_and_connect_node(%Node{
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      available?: true,
      enrollment_date: DateTime.utc_now(),
      network_patch: "AAA",
      authorization_date: DateTime.utc_now(),
      authorized?: true,
      reward_address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
    })

    Crypto.generate_deterministic_keypair("daily_nonce_seed")
    |> elem(0)
    |> NetworkLookup.set_daily_nonce_public_key(DateTime.utc_now() |> DateTime.add(-10))

    assert :ok = NetworkInit.init_software_origin_chain()

    assert 1 == SharedSecrets.list_origin_public_keys() |> Enum.count()

    assert_receive {:transaction,
                    %Transaction{
                      type: :origin,
                      data: %TransactionData{
                        content: content
                      }
                    }}

    {origin_public_key, _rest} = Archethic.Utils.deserialize_public_key(content)
    assert origin_public_key in @genesis_origin_public_keys
  end
end
