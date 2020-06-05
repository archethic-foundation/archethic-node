defmodule UnirisCore.Mining.StampTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Crypto
  alias UnirisCore.Mining.Stamp
  alias UnirisCore.Mining.Fee
  alias UnirisCore.Mining.ProofOfIntegrity

  test "create_validation_stamp/8 should create a signed validation stamp" do
    tx = %Transaction{
      address: "A9BCEB532873BAB3BDF5DD41594CC57CE0AC5E1073B50F4CE3FA6DDF4F3DD2F1",
      type: :transfer,
      timestamp: 1_582_591_494,
      data: %{
        ledger: %{
          uco: %{
            transfers: [
              %{to: "D764BD45B853C689E2BA6D0357E2314F087E402F1F66449B282E5DEDB827EAFD", amount: 5}
            ]
          }
        }
      },
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    unspent_outputs = [
      %Transaction{
        address: "239CCBB96728772F42C5DC3E1AC236208CDA2E8AAD3EF0FF8838081A7AFD4AF9",
        type: :transfer,
        timestamp: 1_582_591_506,
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

    chain = [
      %Transaction{
        address: "4A3FE2512D43D40E80D947867428DD17EDBF72D93E9673A4382A638161081063",
        type: :transfer,
        timestamp: 1_582_591_518,
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: "",
        validation_stamp: %ValidationStamp{
          proof_of_work: "DA96299EC4777FB122E5CF127AAE58020617EC42D3A8F59A63F7A897C46CB52C",
          proof_of_integrity: "44EF4E8E43B08B6E18A691D8F9A5F8822ECAD1D8C7FE7BAC798FF632F821AC80",
          ledger_movements: %LedgerMovements{},
          node_movements: %NodeMovements{
            fee: 1.0,
            rewards: []
          },
          signature:
            "4B38788522E29C3ED6D06FFD406B2E0D1479BF53A98A08F3E97BF6BF8020165012F95DA012913B92FB387B71F9324514E688D85FCD7FEB03CB376D3A31F4EF52"
        }
      }
    ]

    %ValidationStamp{} =
      Stamp.create_validation_stamp(
        tx,
        chain,
        unspent_outputs,
        "welcome_node_public_key",
        "coordinator_public_key",
        ["validator_public_key"],
        ["storage_node_public_key"]
      )
  end

  test "check_validation_stamp_signature/2 should return :ok if successed" do
    pub = Crypto.node_public_key()

    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    stamp =
      Stamp.create_validation_stamp(
        tx,
        [],
        [],
        pub,
        pub,
        [pub],
        []
      )

    assert :ok = Stamp.check_validation_stamp_signature(stamp, pub)
  end

  test "check_validation_stamp_proof_of_integrity/2 should return ok when the proof of integrity validate the chain" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    chain = [
      %Transaction{
        address: "",
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: "",
        validation_stamp: %ValidationStamp{
          proof_of_work: :crypto.strong_rand_bytes(32),
          proof_of_integrity: :crypto.strong_rand_bytes(32),
          ledger_movements: %LedgerMovements{},
          node_movements: %NodeMovements{
            fee: 1.0,
            rewards: []
          },
          signature: :crypto.strong_rand_bytes(32)
        }
      }
    ]

    poi = ProofOfIntegrity.compute([tx | chain])
    assert :ok = Stamp.check_validation_stamp_proof_of_integrity([tx | chain], poi)
    :ok
  end

  test "check_validation_stamp_fee/2 should return ok when the expected fee is the computed one" do
    assert :ok =
             %Transaction{
               address: :crypto.strong_rand_bytes(32),
               type: :transfer,
               timestamp: DateTime.utc_now(),
               data: %{},
               previous_public_key: :crypto.strong_rand_bytes(32),
               previous_signature: :crypto.strong_rand_bytes(64),
               origin_signature: :crypto.strong_rand_bytes(64)
             }
             |> Stamp.check_validation_stamp_fee(0.0)
             # TODO: replace when the fee will be applied (with P2P payments)
  end

  test "check_validation_stamp_rewards/3 should return :ok when the rewards are the same as expected" do
    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: "storage_key1",
      first_public_key: "storage_key1",
      available?: true,
      ready?: true
    })

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
      Fee.distribute(
        # TODO: replace when the fee will be applied (with P2P payments)
        0.0,
        "welcome_key1",
        "coordinator_key1",
        ["validator_key1", "validator_key2"],
        ["storage_key1"]
      )

    assert Stamp.check_validation_stamp_rewards(tx, validation_nodes, rewards) == :ok
  end

  test "check_validation_ledger_movements/4 should return :ok when the ledger movements provided is the expected one by
  computing an UTXO model" do
    previous_ledger = %LedgerMovements{
      uco: %UTXO{}
    }

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

    next_ledger = LedgerMovements.new(tx, 0.1, previous_ledger, unspent_outputs)

    assert :ok =
             Stamp.check_validation_stamp_ledger_movements(
               tx,
               previous_ledger,
               unspent_outputs,
               next_ledger
             )
  end

  test "create_cross_validation_stamp/2 should return a list of inconsistencies signed or the validation stamp signed" do
    stamp = %ValidationStamp{
      proof_of_work: "A9BCEB532873BAB3BDF5DD41594CC57CE0AC5E1073B50F4CE3FA6DDF4F3DD2F1",
      proof_of_integrity: "239CCBB96728772F42C5DC3E1AC236208CDA2E8AAD3EF0FF8838081A7AFD4AF9",
      ledger_movements: %LedgerMovements{},
      node_movements: %NodeMovements{
        fee: 0.1,
        rewards: []
      },
      signature:
        "D8DCCFFDF472DBCA8C1DA0D819A77BEF34A4804D3576791FB3490678C2B3FBCBBC10EB997B35523998B20C2C802AA38DD9A9BBD365E52434DED76137A6611777"
    }

    {sig, [], pub} = Stamp.create_cross_validation_stamp(stamp, [])
    assert Crypto.verify(sig, stamp, pub)
  end

  test "valid_cross_validation_stamp? return true when the stamp is cryptographically valid" do
    stamp = %ValidationStamp{
      proof_of_work: "A9BCEB532873BAB3BDF5DD41594CC57CE0AC5E1073B50F4CE3FA6DDF4F3DD2F1",
      proof_of_integrity: "239CCBB96728772F42C5DC3E1AC236208CDA2E8AAD3EF0FF8838081A7AFD4AF9",
      ledger_movements: %LedgerMovements{},
      node_movements: %NodeMovements{
        fee: 0.1,
        rewards: []
      },
      signature:
        "D8DCCFFDF472DBCA8C1DA0D819A77BEF34A4804D3576791FB3490678C2B3FBCBBC10EB997B35523998B20C2C802AA38DD9A9BBD365E52434DED76137A6611777"
    }

    cross_stamp = Stamp.create_cross_validation_stamp(stamp, [])

    assert Stamp.valid_cross_validation_stamp?(
             cross_stamp,
             stamp
           )
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

    pub = Crypto.node_public_key()

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: "storage_key1",
      first_public_key: "storage_key1",
      available?: true,
      ready?: true
    })

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
          {"storage_key1", 0}
        ]
      }
    }

    sig = Crypto.sign_with_node_key(stamp)
    stamp = Map.put(stamp, :signature, sig)

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

  test "atomic_commitment?/1 should return true when all the cross validation stamps inconsistencies are identical" do
    assert true ==
             Stamp.atomic_commitment?([
               {"", [], ""},
               {"", [], ""},
               {"", [], ""}
             ])
  end

  test "atomic_commitment?/1 should return false when event one of the cross validation stamps inconsistencies is not identical" do
    assert false ==
             Stamp.atomic_commitment?([
               {"", [:invalid_signature], ""},
               {"", [], ""},
               {"", [], ""}
             ])

    assert false ==
             Stamp.atomic_commitment?([
               {"", [:invalid_signature], ""},
               {"", [:invalid_rewarded_nodes], ""},
               {"", [], ""}
             ])

    assert false ==
             Stamp.atomic_commitment?([
               {"", [:invalid_signature], ""},
               {"", [:invalid_rewarded_nodes], ""},
               {"", [:invalid_signature], ""}
             ])
  end
end
