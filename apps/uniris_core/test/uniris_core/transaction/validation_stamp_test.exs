defmodule UnirisCore.Transaction.ValidationStampTest do
  use UnirisCoreCase

  import Mox

  alias UnirisCore.Crypto

  alias UnirisCore.Mining.Context

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger

  doctest ValidationStamp

  test "new/5 should create a signed validation stamp" do
    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to: "D764BD45B853C689E2BA6D0357E2314F087E402F1F66449B282E5DEDB827EAFD",
                  amount: 5
                }
              ]
            }
          }
        },
        "seed",
        0
      )

    unspent_outputs = [
      %UnspentOutput{
        amount: 10,
        from: :crypto.strong_rand_bytes(32)
      }
    ]

    chain = [
      %Transaction{
        address: "4A3FE2512D43D40E80D947867428DD17EDBF72D93E9673A4382A638161081063",
        type: :transfer,
        timestamp: ~U[2020-02-25 00:45:18Z],
        data: %TransactionData{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: "",
        validation_stamp: %ValidationStamp{
          proof_of_work: "DA96299EC4777FB122E5CF127AAE58020617EC42D3A8F59A63F7A897C46CB52C",
          proof_of_integrity: "44EF4E8E43B08B6E18A691D8F9A5F8822ECAD1D8C7FE7BAC798FF632F821AC80",
          ledger_operations: %LedgerOperations{},
          signature:
            "4B38788522E29C3ED6D06FFD406B2E0D1479BF53A98A08F3E97BF6BF8020165012F95DA012913B92FB387B71F9324514E688D85FCD7FEB03CB376D3A31F4EF52"
        }
      }
    ]

    assert %ValidationStamp{
             signature: _,
             proof_of_work: _,
             proof_of_integrity: _,
             ledger_operations: %LedgerOperations{}
           } =
             ValidationStamp.new(
               tx,
               %Context{
                 previous_chain: chain,
                 unspent_outputs: unspent_outputs,
                 involved_nodes: ["storage_node_public_key"]
               },
               "welcome_node_public_key",
               "coordinator_public_key",
               ["cross_validator_public_key"]
             )
  end

  test "valid_signature?/2 return true when the signature is valid" do
    {pub, pv} = Crypto.generate_deterministic_keypair("seed", :secp256r1)

    MockCrypto
    |> expect(:sign_with_node_key, fn data ->
      Crypto.sign(data, pv)
    end)

    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  to: "D764BD45B853C689E2BA6D0357E2314F087E402F1F66449B282E5DEDB827EAFD",
                  amount: 5
                }
              ]
            }
          }
        },
        "seed",
        0
      )

    unspent_outputs = [
      %UnspentOutput{
        amount: 10,
        from: :crypto.strong_rand_bytes(32)
      }
    ]

    assert ValidationStamp.new(
             tx,
             %Context{
               previous_chain: [],
               unspent_outputs: unspent_outputs,
               involved_nodes: ["storage_node_public_key"]
             },
             "welcome_node_public_key",
             Crypto.node_public_key(),
             ["validator_public_key"]
           )
           |> ValidationStamp.valid_signature?(pub)
  end

  describe "inconsistencies/5" do
    setup do
      P2P.add_node(%Node{
        first_public_key: "storage_key1",
        last_public_key: "storage_key1",
        ip: {127, 0, 0, 1},
        port: 3000,
        ready?: true
      })

      :ok
    end

    test "should return no  inconsistencies when the validation stamp is valid" do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [%Transfer{to: :crypto.strong_rand_bytes(32), amount: 5}]
              }
            }
          },
          "seed",
          0
        )

      utxo = [
        %UnspentOutput{
          amount: 10,
          from: :crypto.strong_rand_bytes(32)
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
            ledger_operations: %LedgerOperations{},
            signature: :crypto.strong_rand_bytes(32)
          }
        }
      ]

      assert [] ==
               ValidationStamp.new(
                 tx,
                 %Context{
                   previous_chain: previous_chain,
                   unspent_outputs: utxo,
                   involved_nodes: ["storage_key1"]
                 },
                 "welcome_node_public_key",
                 Crypto.node_public_key(),
                 ["cross_validator_public_key"]
               )
               |> ValidationStamp.inconsistencies(
                 tx,
                 Crypto.node_public_key(),
                 ["cross_validator_public_key"],
                 %Context{
                   previous_chain: previous_chain,
                   unspent_outputs: utxo
                 }
               )
    end

    test "should return inconsistencies when the validation stamp is not valid" do
      tx =
        Transaction.new(
          :transfer,
          %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [%Transfer{to: :crypto.strong_rand_bytes(32), amount: 5}]
              }
            }
          },
          "seed",
          0
        )

      utxo = [
        %UnspentOutput{
          amount: 10,
          from: :crypto.strong_rand_bytes(32)
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
            ledger_operations: %LedgerOperations{},
            signature: :crypto.strong_rand_bytes(32)
          }
        }
      ]

      stamp = %ValidationStamp{
        ledger_operations: %LedgerOperations{
          node_movements: [
            %NodeMovement{
              to: :crypto.strong_rand_bytes(32),
              amount: 100
            }
          ],
          fee: 0.0
        },
        signature: "",
        proof_of_work: "",
        proof_of_integrity: ""
      }

      assert [:signature, :proof_of_integrity, :ledger_operations] ==
               ValidationStamp.inconsistencies(
                 stamp,
                 tx,
                 Crypto.node_public_key(),
                 ["cross_validator_public_key"],
                 %Context{
                   previous_chain: previous_chain,
                   unspent_outputs: utxo
                 }
               )
    end
  end
end
