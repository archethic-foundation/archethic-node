defmodule UnirisCore.Mining.ReplicationTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Mining.Replication
  alias UnirisCore.Mining.Fee
  alias UnirisCore.Mining.ProofOfIntegrity
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisCore.Crypto
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Election

  import Mox

  test "tree/2 create tree of storage nodes grouped by the closest validation nodes" do
    validation_nodes = [
      %{network_patch: "AC2", last_public_key: "key_v1"},
      %{network_patch: "DF3", last_public_key: "key_v2"},
      %{network_patch: "C22", last_public_key: "key_v3"},
      %{network_patch: "E19", last_public_key: "key_v4"},
      %{network_patch: "22A", last_public_key: "key_v5"}
    ]

    storage_nodes = [
      %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
      %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
      %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
      %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
      %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
      %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
      %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
      %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"},
      %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
      %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
      %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"},
      %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
      %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"},
      %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"},
      %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
      %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
    ]

    tree = Replication.tree(validation_nodes, storage_nodes)

    assert tree ==
             %{
               "key_v1" => [
                 %{network_patch: "A23", first_public_key: "key_S2", last_public_key: "key_S2"},
                 %{network_patch: "B43", first_public_key: "key_S3", last_public_key: "key_S3"},
                 %{network_patch: "A63", first_public_key: "key_S7", last_public_key: "key_S7"},
                 %{network_patch: "AA0", first_public_key: "key_S14", last_public_key: "key_S14"}
               ],
               "key_v2" => [
                 %{network_patch: "D32", first_public_key: "key_S8", last_public_key: "key_S8"}
               ],
               "key_v3" => [
                 %{network_patch: "BB2", first_public_key: "key_S6", last_public_key: "key_S6"},
                 %{network_patch: "C2A", first_public_key: "key_S10", last_public_key: "key_S10"},
                 %{network_patch: "C23", first_public_key: "key_S11", last_public_key: "key_S11"}
               ],
               "key_v4" => [
                 %{network_patch: "F36", first_public_key: "key_S1", last_public_key: "key_S1"},
                 %{network_patch: "F22", first_public_key: "key_S12", last_public_key: "key_S12"},
                 %{network_patch: "E2B", first_public_key: "key_S13", last_public_key: "key_S13"}
               ],
               "key_v5" => [
                 %{network_patch: "2A9", first_public_key: "key_S4", last_public_key: "key_S4"},
                 %{network_patch: "143", first_public_key: "key_S5", last_public_key: "key_S5"},
                 %{network_patch: "19A", first_public_key: "key_S9", last_public_key: "key_S9"},
                 %{network_patch: "042", first_public_key: "key_S15", last_public_key: "key_S15"},
                 %{network_patch: "3BC", first_public_key: "key_S16", last_public_key: "key_S16"}
               ]
             }
  end

  test "chain_validation/1 should performs the transaction chain validation" do
    tx = %{
      address:
        <<0, 65, 9, 62, 32, 153, 130, 11, 166, 32, 35, 227, 206, 83, 128, 215, 234, 180, 244, 7,
          135, 104, 16, 239, 82, 32, 33, 7, 240, 127, 111, 29, 27>>,
      type: :transfer,
      timestamp: 1_600_562_750,
      data: %{}
    }

    {previous_pub, previous_pv} = Crypto.generate_deterministic_keypair("transaction_seed")
    tx = Map.put(tx, :previous_signature, Crypto.sign(tx, previous_pv))
    tx = Map.put(tx, :previous_public_key, previous_pub)

    {origin_pub, origin_pv} = Crypto.generate_deterministic_keypair("origin_seed")
    tx = struct(Transaction, Map.put(tx, :origin_signature, Crypto.sign(tx, origin_pv)))

    unspent_outputs = [
      %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{to: tx.address, amount: 11}
              ]
            }
          }
        },
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      }
    ]

    previous_tx = %Transaction{
      address: Crypto.hash(tx.previous_public_key),
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    previous_tx =
      Map.put(previous_tx, :validation_stamp, %ValidationStamp{
        proof_of_work: :crypto.strong_rand_bytes(32),
        proof_of_integrity: ProofOfIntegrity.compute([previous_tx]),
        ledger_movements: %LedgerMovements{},
        node_movements: %NodeMovements{fee: 1, rewards: []},
        signature: ""
      })

    previous_chain = [previous_tx]

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          [{:ok, previous_chain}, {:ok, unspent_outputs}]
      end
    end)

    {validator_pub, validator_pv} = Crypto.generate_deterministic_keypair("other_seed")

    [
      %Node{
        last_public_key: "storage_node_key1",
        available?: true,
        network_patch: "AFA",
        first_public_key: "storage_node_key1",
        ip: {127, 0, 0, 1},
        port: 3000,
        geo_patch: "",
        average_availability: 1,
        ready?: true
      },
      %Node{
        last_public_key: "storage_node_key2",
        first_public_key: "storage_node_key2",
        available?: true,
        network_patch: "DCA",
        average_availability: 1,
        ip: {127, 0, 0, 1},
        port: 3000,
        geo_patch: "",
        ready?: true
      },
      %Node{
        first_public_key: Crypto.node_public_key(0),
        last_public_key: Crypto.node_public_key(),
        available?: true,
        network_patch: "ACA",
        geo_patch: "",
        average_availability: 1,
        ip: {127, 0, 0, 1},
        port: 3000,
        ready?: true,
        authorized?: true
      },
      %Node{
        first_public_key: validator_pub,
        last_public_key: validator_pub,
        available?: true,
        network_patch: "ADA",
        ip: {127, 0, 0, 1},
        port: 3000,
        average_availability: 1,
        geo_patch: "AAA",
        ready?: true,
        authorized?: true
      }
    ]
    |> Enum.each(&P2P.add_node/1)

    [coordinator | cross_validation_nodes] =
      Election.validation_nodes(tx) |> Enum.map(& &1.last_public_key)

    validation_stamp =
      ValidationStamp.new(
        origin_pub,
        ProofOfIntegrity.compute([tx | previous_chain]),
        %NodeMovements{
          # TODO: replace when the fee will be applied (with P2P payments)
          fee: 0.0,
          rewards:
            Fee.distribute(
              # TODO: replace when the fee will be applied (with P2P payments)
              0.0,
              Crypto.node_public_key(),
              coordinator,
              cross_validation_nodes,
              Election.storage_nodes(List.first(previous_chain).address)
              |> Enum.map(& &1.last_public_key)
            )
        },
        %LedgerMovements{
          uco: %UTXO{
            # TODO: replace when the fee will be applied (with P2P payments)
            next: 11.0,
            previous: %{
              amount: 11,
              from: [
                List.first(unspent_outputs).address
              ]
            }
          }
        }
      )

    cross_validation_stamp =
      if List.first(cross_validation_nodes) == Crypto.node_public_key() do
        {Crypto.sign_with_node_key(validation_stamp), [], Crypto.node_public_key()}
      else
        {Crypto.sign(validation_stamp, validator_pv), [], validator_pub}
      end

    validated_tx = %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: [cross_validation_stamp]
    }

    assert {:ok, [validated_tx | previous_chain]} = Replication.chain_validation(validated_tx)
  end

  test "transaction_validation_only/1 should validate the validated transaction itself" do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    validation_stamp =
      ValidationStamp.new(
        Crypto.node_public_key(0),
        Crypto.hash(tx),
        %NodeMovements{
          # TODO: replace when the fee will be applied (with P2P payments)
          fee: 0.0,
          rewards:
            Fee.distribute(
              # TODO: replace when the fee will be applied (with P2P payments)
              0.0,
              Crypto.node_public_key(),
              Crypto.node_public_key(),
              [Crypto.node_public_key()],
              []
            )
        },
        %LedgerMovements{}
      )

    cross_validation_stamp =
      {Crypto.sign_with_node_key(validation_stamp), [], Crypto.node_public_key()}

    validated_tx = %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: [cross_validation_stamp]
    }

    assert :ok = Replication.transaction_validation_only(validated_tx)
  end
end
