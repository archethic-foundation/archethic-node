defmodule UnirisValidation.DefaultImplTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.Data.Ledger
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisCrypto, as: Crypto
  alias UnirisValidation.DefaultImpl.ProofOfWork
  alias UnirisValidation.DefaultImpl.ProofOfIntegrity
  alias UnirisValidation.DefaultImpl.Fee
  alias UnirisValidation.DefaultImpl.Reward
  alias UnirisNetwork.Node

  alias UnirisValidation.DefaultImpl, as: Validation

  import Mox

  setup :verify_on_exit!

  test "start_validation/1 should start a mining process under the dynamic supervisor" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    Validation.start_validation(tx, "welcome_node_public_key", [
      "validator_key1",
      "validator_key2"
    ])

    assert 1 == DynamicSupervisor.count_children(UnirisValidation.MiningSupervisor).active

    [{_, pid, :worker, [UnirisValidation.DefaultImpl.Mining]}] =
      DynamicSupervisor.which_children(UnirisValidation.MiningSupervisor)

    assert Process.alive?(pid)
  end

  test "replicate_transaction/1 should verify the transaction and store it if ok" do

    origin_keyspairs = [
      {<<0, 195, 84, 216, 212, 203, 243, 221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19,
         136, 12, 49, 220, 138, 27, 238, 216, 110, 230, 9, 61, 135>>,
       <<0, 185, 223, 241, 198, 63, 175, 22, 169, 80, 250, 126, 230, 19, 143, 48, 78, 154, 81, 15,
         70, 197, 195, 14, 144, 116, 203, 211, 27, 237, 151, 18, 174, 195, 84, 216, 212, 203, 243,
         221, 69, 12, 73, 56, 72, 36, 182, 126, 169, 181, 57, 19, 136, 12, 49, 220, 138, 27, 238,
         216, 110, 230, 9, 61, 135>>}
    ]

    [{origin_public_key, _}] = origin_keyspairs

    Crypto.SoftwareImpl.load_origin_keys(origin_keyspairs)

    tx =
      Transaction.new(:transfer, %Data{
        ledger: %Ledger{
          uco: %UCO{
            transfers: [
              %Transfer{to: :crypto.strong_rand_bytes(32), amount: 10}
            ]
          }
        }
      })

    unspent_outputs = [
      %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{
          ledger: %{
            uco: %{
              transfers: [
                %{to: tx.address, amount: 11}
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

    previous_tx = %{
      previous_tx
      | validation_stamp: %ValidationStamp{
          proof_of_work: :crypto.strong_rand_bytes(32),
          proof_of_integrity: ProofOfIntegrity.from_transaction(previous_tx),
          ledger_movements: %LedgerMovements{uco: %UTXO{}},
          node_movements: %NodeMovements{fee: 1, rewards: []},
          signature: ""
        }
    }

    previous_chain = [previous_tx]

    MockNetwork
    |> stub(:origin_public_keys, fn -> [origin_public_key] end)
    |> stub(:list_nodes, fn -> [] end)
    |> stub(:storage_nonce, fn -> "" end)
    |> stub(:daily_nonce, fn -> "" end)
    |> stub(:node_info, fn _ ->
      %Node{
        first_public_key: "node",
        last_public_key: "node",
        availability: 1,
        network_patch: "ADA",
        average_availability: 1,
        ip: "",
        port: 3000,
        geo_patch: ""
      }
    end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:ok, previous_chain}, {:ok, unspent_outputs}]}
      end
    end)

    coordinator_pub = Crypto.last_node_public_key()

    MockElection
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node_key1",
          availability: 1,
          network_patch: "AFA",
          first_public_key: "storage_node_key1",
          ip: "",
          port: 3000,
          geo_patch: "",
          average_availability: 1
        },
        %Node{
          last_public_key: "storage_node_key2",
          first_public_key: "storage_node_key2",
          availability: 1,
          network_patch: "DCA",
          average_availability: 1,
          ip: "",
          port: 3000,
          geo_patch: ""
        }
      ]
    end)
    |> expect(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: coordinator_pub,
          last_public_key: coordinator_pub,
          availability: 1,
          network_patch: "ACA",
          geo_patch: "",
          average_availability: 1,
          ip: "",
          port: 3000
        },
        %Node{
          first_public_key: "validator_key2",
          last_public_key: "validator_key2",
          availability: 1,
          network_patch: "ADA",
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        }
      ]
    end)

    me = self()

    MockChain
    |> stub(:store_transaction_chain, fn _chain ->
      send(me, :store)
      :ok
    end)

    {:ok, pow} = ProofOfWork.run(tx)
    poi = ProofOfIntegrity.from_chain([tx | previous_chain])
    fee = Fee.from_transaction(tx)

    node_movements = %NodeMovements{
      fee: fee,
      rewards:
        Reward.distribute_fee(fee, "welcome_node_key", coordinator_pub, ["validator_key2"], [
          "storage_node_key1",
          "storage_node_key2"
        ])
    }

    ledger_movements = %LedgerMovements{
      uco: %UTXO{
        previous: %{from: [List.first(unspent_outputs).address], amount: 11},
        next: 0.9000000000000004
      }
    }

    stamp = ValidationStamp.new(pow, poi, ledger_movements, node_movements)

    pub = Crypto.generate_random_keypair(persistence: true)
    sig = Crypto.sign(stamp, with: :node, as: :last)
    validated_tx = %{tx | validation_stamp: stamp, cross_validation_stamps: [{sig, [], pub}]}

    assert :ok == Validation.replicate_transaction(validated_tx)
    assert_received :store
  end
end
