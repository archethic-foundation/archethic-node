defmodule UnirisCore.Mining.ContextTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.Crypto
  alias UnirisCore.Mining.Context
  alias UnirisCore.P2P.NodeSupervisor

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      ip: {127, 0, 0, 1},
      port: 3000,
      ready?: true,
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    P2P.add_node(%Node{
      last_public_key: "key1",
      first_public_key: "key1",
      network_patch: "AA0",
      ip: {88, 100, 200, 15},
      port: 3000,
      average_availability: 1,
      availability: 1,
      geo_patch: "AAC",
      ready?: true
    })

    P2P.add_node(%Node{
      last_public_key: "key3",
      first_public_key: "key3",
      network_patch: "AAA",
      ip: {150, 10, 20, 32},
      port: 3000,
      average_availability: 1,
      availability: 1,
      geo_patch: "AAA",
      ready?: true
    })

    :ok
  end

  test "download/2 should get a list of transaction and unspent outputs and the storage node used" do
    MockNodeClient
    |> stub(:send_message, fn _, _ ->
      [{:ok, [%{}]}, {:ok, [%{}]}]
    end)

    assert {:ok, chain, outputs, node} =
             Context.download(:crypto.strong_rand_bytes(32), P2P.list_nodes())
  end

  test "confirm/2 should return previous chain, unspent outputs with storage nodes used for data retrieeval and data confirmation" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "699590B5CE098EDA80BC1140595AAB437E75D3B6C88255D4D40D1CA1B4AC1A94",
      previous_signature: "",
      origin_signature: ""
    }

    unspent_outputs = [
      %Transaction{
        address: "C52B3A9210B218DE7C6FD1973B42AC282DD0D67A375B1267D67A40A1227682F3",
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: ""
      }
    ]

    previous_chain = [
      %Transaction{
        address: Crypto.hash(tx.previous_public_key),
        type: :transfer,
        timestamp: DateTime.utc_now(),
        data: %{},
        previous_public_key: "",
        previous_signature: "",
        origin_signature: "",
        validation_stamp: %ValidationStamp{
          proof_of_work: :crypto.strong_rand_bytes(32),
          proof_of_integrity: :crypto.strong_rand_bytes(32),
          ledger_movements: %LedgerMovements{uco: %UTXO{}},
          node_movements: %NodeMovements{fee: 1, rewards: []},
          signature: ""
        }
      }
    ]

    MockNodeClient
    |> stub(:send_message, fn _, msg ->
      case msg do
        {:get_proof_of_integrity, _} ->
          {:ok, List.first(previous_chain).validation_stamp.proof_of_integrity}

        {:get_transaction, _} ->
          {:ok, List.first(unspent_outputs)}
      end
    end)

    {:ok, chain, unspent_output_transactions, nodes} =
      Context.confirm(
        {:ok, previous_chain, unspent_outputs, "key3"},
        ["key3", "key1"]
      )

    assert chain == previous_chain
    assert unspent_outputs == unspent_output_transactions

    assert nodes == [
             # previous storage node used to retreive the chain and utxo
             "key3",
             # previous storage node used to confirm the chain integrity
             "key1"
           ]
  end
end
