defmodule UnirisValidation.ContextBuildingTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisValidation.ContextBuilding
  alias UnirisNetwork.Node
  alias UnirisCrypto, as: Crypto

  import Mox

  setup :verify_on_exit!

  test "download_transaction_context/2 should get a list of transaction and unspent outputs and the storage node used" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    storage_nodes = [
      %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        ip: "",
        port: 3000,
        geo_patch: "AAA",
        average_availability: 1,
        availability: 1
      }
    ]

    MockNetwork
    |> expect(:send_message, fn _, _ ->
      {:ok, [{:ok, [%{}]}, {:ok, [%{}]}]}
    end)

    assert {:ok, chain, outputs, node} =
             ContextBuilding.download_transaction_context(tx, storage_nodes)
  end

  test "with_confirmation/1 should return previous chain, unspent outputs with storage nodes used for data retrieeval and data confirmation" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: :crypto.strong_rand_bytes(32),
      previous_signature: "",
      origin_signature: ""
    }

    unspent_outputs = [
      %Transaction{
        address: :crypto.strong_rand_bytes(32),
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

    MockNetwork
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:ok, previous_chain}, {:ok, unspent_outputs}]}

        {:get_proof_of_integrity, _} ->
          {:ok, List.first(previous_chain).validation_stamp.proof_of_integrity}

        {:get_transaction, _} ->
          {:ok, List.first(unspent_outputs)}
      end
    end)

    MockNetwork
    |> stub(:list_nodes, fn -> [] end)
    |> stub(:storage_nonce, fn -> "" end)
    |> stub(:node_info, fn _ ->
      %Node{
        last_public_key: "key1",
        first_public_key: "key1",
        network_patch: "AA0",
        geo_patch: "AAA",
        ip: "88.100.200.10",
        port: 3000,
        average_availability: 1,
        availability: 1
      }
    end)

    MockElection
    |> stub(:storage_nodes, fn addr, _, _, _ ->
      if addr == List.first(previous_chain).address do
        [
          %Node{
            last_public_key: "key1",
            first_public_key: "key1",
            network_patch: "AA0",
            ip: "88.100.200.15",
            port: 3000,
            average_availability: 1,
            availability: 1,
            geo_patch: "AAC"
          },
          %Node{
            last_public_key: "key2",
            first_public_key: "key2",
            network_patch: "FD3",
            ip: "200.10.52.32",
            port: 3000,
            average_availability: 1,
            availability: 1,
            geo_patch: "FAC"
          }
        ]
      else
        [
          %Node{
            last_public_key: "key3",
            first_public_key: "key3",
            network_patch: "54A",
            ip: "50.10.127.12",
            port: 3000,
            average_availability: 1,
            availability: 1,
            geo_patch: "ACA"
          }
        ]
      end
    end)

    {:ok, chain, unspent_output_transactions, nodes} = ContextBuilding.with_confirmation(tx)
    assert chain == previous_chain
    assert unspent_outputs == unspent_output_transactions

    assert Enum.map(nodes, & &1.last_public_key) == [
             # previous storage node used to retreive the chain and utxo
             "key1",
             # previous storage node used to confirm the chain integrity
             "key2",
             # previous storage node to confirm the utxo
             "key3"
           ]
  end
end
