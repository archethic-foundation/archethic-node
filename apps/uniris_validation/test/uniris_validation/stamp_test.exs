defmodule UnirisValidation.StampTest do
  use ExUnit.Case
  doctest UnirisValidation.Stamp

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO

  alias UnirisCrypto, as: Crypto
  alias UnirisValidation.Stamp
  alias UnirisValidation.Reward

  import Mox

  setup :verify_on_exit!

  test "check_validation_stamp_rewards/3 should return :ok when the rewards are the same as expected" do
    storage_nodes = [
      %{last_public_key: "storage_key1"},
      %{last_public_key: "storage_key2"},
      %{last_public_key: "storage_key3"}
    ]

    MockNetwork
    |> expect(:list_nodes, fn -> [] end)
    |> expect(:storage_nonce, fn -> "" end)

    MockElection
    |> expect(:storage_nodes, fn _, _, _, _ ->
      storage_nodes
    end)

    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{
        ledger: %{
          uco: %{
            transfers: [%{to: :crypto.strong_rand_bytes(32), amount: 10}]
          }
        }
      },
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    validation_nodes = ["validator_key1", "validator_key2"]

    rewards =
      Reward.distribute_fee(
        0.1,
        "welcome_key1",
        "coordinator_key1",
        ["validator_key1", "validator_key2"],
        ["storage_key1", "storage_key2"]
      )

    assert Stamp.check_validation_stamp_rewards(tx, validation_nodes, rewards) == :ok
  end

  test "check_validation_stamp/6 should return list of inconsistencies when there is failure during the subset checks" do
    tx = %Transaction{
      address: :crypto.strong_rand_bytes(32),
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{
        ledger: %{
          uco: %{
            transfers: [%{to: :crypto.strong_rand_bytes(32), amount: 5}]
          }
        }
      },
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    unspent_outputs = [
      %Transaction{
        address: :crypto.strong_rand_bytes(32),
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{
          ledger: %{
            uco: %{
              transfers: [%{to: tx.address, amount: 10}]
            }
          }
        },
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      }
    ]

    previous_chain = [
      %Transaction{
        address: "",
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: "",
        validation_stamp: %ValidationStamp{
          proof_of_work: <<0::8>> <> :crypto.strong_rand_bytes(32),
          proof_of_integrity: :crypto.strong_rand_bytes(32),
          ledger_movements: %LedgerMovements{
            uco: %UTXO{
              previous: %{from: [""], amount: 10},
              next: 5
            }
          },
          node_movements: %NodeMovements{
            fee: 1.0,
            rewards: []
          },
          signature: :crypto.strong_rand_bytes(32)
        }
      }
    ]

    pub = Crypto.generate_random_keypair(persistence: true)

    stamp = %{
      proof_of_work: <<0::8>> <> :crypto.strong_rand_bytes(32),
      proof_of_integrity: :crypto.strong_rand_bytes(32),
      ledger_movements: %LedgerMovements{
        uco: %UTXO{}
      },
      node_movements: %NodeMovements{
        fee: 1.0,
        rewards: [
          {"welcome_key1", 0},
          {"coordinator_key", 0},
          {"validator_key1", 10},
          {"validator_key2", 10},
          {"storage_key1", 0},
          {"storage_key2", 0}
        ]
      }
    }

    sig = Crypto.sign(stamp, with: :node, as: :last)
    stamp = Map.put(stamp, :signature, sig)

    storage_nodes = [
      %{last_public_key: "storage_key1"},
      %{last_public_key: "storage_key2"},
      %{last_public_key: "storage_key3"}
    ]

    MockNetwork
    |> expect(:list_nodes, fn -> [] end)
    |> expect(:storage_nonce, fn -> "" end)

    MockElection
    |> expect(:storage_nodes, fn _, _, _, _ ->
      storage_nodes
    end)

    {:error, inconsistencies} =
      Stamp.check_validation_stamp(
        tx,
        struct(ValidationStamp, stamp),
        pub,
        [%{last_public_key: "validator_key1"}, %{last_public_key: "validation_key2"}],
        previous_chain,
        unspent_outputs
      )

    assert [
             :invalid_proof_of_work,
             :invalid_proof_of_integrity,
             :invalid_fee,
             :invalid_rewarded_nodes,
             :invalid_ledger_movements
           ]
           |> Enum.all?(&(&1 in inconsistencies))
  end
end
