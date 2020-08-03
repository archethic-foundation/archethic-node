defmodule Uniris.Bootstrap.NetworkInitTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.Beacon
  alias Uniris.BeaconSlot
  alias Uniris.BeaconSlot.TransactionInfo
  alias Uniris.BeaconSubset
  alias Uniris.BeaconSubsetRegistry
  alias Uniris.BeaconSubsets

  alias Uniris.Bootstrap.NetworkInit
  alias Uniris.Mining.Context

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Storage.Cache

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionData
  alias Uniris.TransactionData.Ledger
  alias Uniris.TransactionData.Ledger.Transfer
  alias Uniris.TransactionData.UCOLedger

  import Mox

  setup do
    Enum.each(BeaconSubsets.all(), &BeaconSubset.start_link(subset: &1))
    :ok
  end

  test "create_storage_nonce/0 should initialize the nonce in the crypto keystore" do
    me = self()

    MockCrypto
    |> expect(:node_public_key, fn ->
      {pub, _} = Crypto.generate_deterministic_keypair("seed", :secp256r1)
      pub
    end)
    |> expect(:decrypt_and_set_storage_nonce, fn _encrypted_nonce ->
      send(me, :encrypted_nonce)
      :ok
    end)

    NetworkInit.create_storage_nonce()
    assert_received :encrypted_nonce
  end

  test "self_validation!/2 should return a validated transaction" do
    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{to: "@Alice2", amount: 5_000.0}
              ]
            }
          }
        },
        "seed",
        0
      )

    %Transaction{
      validation_stamp: %ValidationStamp{
        ledger_operations: %LedgerOperations{
          transaction_movements: [
            %TransactionMovement{to: "@Alice2", amount: 5_000.0}
          ],
          unspent_outputs: [
            # TODO: use the right change when the fee algorithm is implemented
            %UnspentOutput{amount: 4999.9}
          ]
        }
      }
    } =
      NetworkInit.self_validation!(tx, %Context{
        unspent_outputs: [
          %UnspentOutput{amount: 10_000, from: tx.address}
        ]
      })
  end

  test "self_replication/1 should insert the transaction and add to the beacon chain" do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    validated_tx = %{
      tx
      | validation_stamp: %ValidationStamp{
          proof_of_integrity: "",
          proof_of_work: "",
          ledger_operations: %LedgerOperations{},
          signature: ""
        }
    }

    me = self()

    MockStorage
    |> stub(:write_transaction_chain, fn _chain ->
      send(me, :write_transaction)
      :ok
    end)

    NetworkInit.self_replication(validated_tx)

    assert_received :write_transaction

    subset = Beacon.subset_from_address(tx.address)
    [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)

    %{
      current_slot: %BeaconSlot{
        transactions: [
          %TransactionInfo{}
        ]
      }
    } = :sys.get_state(pid)
  end

  test "init_node_shared_secrets_chain/1 should create node shared secrets transaction chain, load daily nonce and authorize node" do
    me = self()

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      available?: true
    })

    MockStorage
    |> expect(:write_transaction_chain, fn [tx] ->
      send(me, {:transaction, tx})
      :ok
    end)

    MockCrypto
    |> expect(:decrypt_and_set_node_shared_secrets_network_pool_seed, fn _, _ ->
      send(me, :set_daily_nonce)
      :ok
    end)

    NetworkInit.init_node_shared_secrets_chain("network_seed")

    assert_receive {:transaction, %Transaction{type: :node_shared_secrets}}
    assert_receive :set_daily_nonce

    assert {:ok, %Node{authorized?: true}} = P2P.node_info()
  end

  test "init_genesis_wallets/1 should initialize genesis wallets" do
    MockStorage
    |> stub(:write_transaction_chain, fn [tx] ->
      Cache.store_transaction(tx)
      :ok
    end)

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      available?: true
    })

    NetworkInit.init_genesis_wallets("@network_pool")

    funding_address =
      "002E354A95241E867C836E8BBBBF6F9BF2450860BA28B1CF24B734EF67FF49169E"
      |> Base.decode16!()
      |> Crypto.hash()

    assert 3.82e9 == Cache.get_ledger_balance(funding_address)
    assert 1.46e9 == Cache.get_ledger_balance("@network_pool")
  end
end
