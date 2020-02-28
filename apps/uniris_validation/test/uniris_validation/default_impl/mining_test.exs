defmodule UnirisValidation.DefaultImpl.Mining.Test do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisValidation.DefaultImpl.Mining
  alias UnirisValidation.DefaultImpl.BinarySequence
  alias UnirisCrypto, as: Crypto
  alias UnirisNetwork.Node

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  test "start_link/1 should start the transaction mining process" do
    tx = %Transaction{
      address: :crypto.strong_rand_bytes(32),
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    {:ok, pid} = Mining.start_link(transaction: tx)
    assert true == Process.alive?(pid)
  end

  test "start_link/1 should state as invalid pending transaction when the pending transaction integrity is not valid" do
    tx = %Transaction{
      address: :crypto.strong_rand_bytes(32),
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "",
        validation_node_public_keys: []
      )

    assert {:invalid_pending_transaction, _} = :sys.get_state(pid)
  end

  test "start_link/1 should state as invalid welcome node election when the list of validation nodes is different than the election algorithm" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    MockNetwork
    |> expect(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> expect(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)

    MockElection
    |> expect(:validation_nodes, fn _, _, _, _ -> [%{last_public_key: "node_key2"}] end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: ["node_key1"]
      )

    assert {:invalid_welcome_node_election, _} = :sys.get_state(pid)
  end

  test "start_link/1 should state as cross validation node and start retrievial of the transaction context" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    MockNetwork
    |> stub(:node_info, fn _ ->
      %Node{
        last_public_key: "node_key1",
        first_public_key: "node_key1",
        network_patch: "AF0",
        ip: "88.100.0.10",
        port: 3000,
        geo_patch: "AAA",
        average_availability: 1,
        availability: 1
      }
    end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: "coordinator_key",
          last_public_key: "coordinator_key",
          ip: '127.0.0.1',
          port: 3000,
          availability: 1,
          geo_patch: "ADA",
          average_availability: 1
        },
        %Node{
          first_public_key: "validator_key",
          last_public_key: "validator_key",
          ip: '88.20.50.1',
          port: 3000,
          availability: 1,
          geo_patch: "AFC",
          average_availability: 1
        }
      ]
    end)
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node1",
          first_public_key: "storage_node1",
          availability: 1,
          geo_patch: "FAC",
          network_patch: "FAA",
          ip: "127.0.0.1",
          port: 3000,
          average_availability: 1
        }
      ]
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: ["coordinator_key", "validator_key"]
      )

    {state, data} = :sys.get_state(pid)
    assert state == :cross_validator

    %{
      validation_nodes_view: validation_nodes_view,
      storage_nodes_view: storage_nodes_view,
      validation_nodes: validation_nodes,
      context_building_task: %Task{}
    } = data

    assert is_bitstring(validation_nodes_view)
    assert is_bitstring(storage_nodes_view)

    assert bit_size(validation_nodes_view) == 1
    assert bit_size(storage_nodes_view) == 1

    assert Enum.map(validation_nodes, & &1.last_public_key) == [
             "coordinator_key",
             "validator_key"
           ]

    assert length(Task.Supervisor.children(UnirisValidation.TaskSupervisor)) == 1

    process =
      Task.Supervisor.children(UnirisValidation.TaskSupervisor) |> Enum.map(&Process.info(&1))

    assert {UnirisValidation.DefaultImpl.ContextBuilding, :with_confirmation, _} =
             process |> List.first() |> get_in([:dictionary, :"$initial_call"])
  end

  test "start_link/1 should state as coordinator, state retrieval of information of the transaction context and start proof of work processing" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    pub = Crypto.last_node_public_key()

    MockNetwork
    |> stub(:node_info, fn _ ->
      %Node{
        last_public_key: "node_key1",
        first_public_key: "node_key1",
        network_patch: "AF0",
        ip: "88.100.0.10",
        port: 3000,
        geo_patch: "AAA",
        average_availability: 1,
        availability: 1
      }
    end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: pub,
          last_public_key: pub,
          ip: '127.0.0.1',
          port: 3000,
          availability: 1,
          geo_patch: "ADA",
          average_availability: 1
        },
        %Node{
          first_public_key: "validator_key",
          last_public_key: "validator_key",
          ip: '88.20.50.1',
          port: 3000,
          availability: 1,
          geo_patch: "AFC",
          average_availability: 1
        }
      ]
    end)
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node1",
          first_public_key: "storage_node1",
          availability: 1,
          geo_patch: "FAC",
          network_patch: "FAA",
          ip: "127.0.0.1",
          port: 3000,
          average_availability: 1
        }
      ]
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: [pub, "validator_key"]
      )

    assert {:coordinator, %{pow_task: %Task{}}} = :sys.get_state(pid)
    assert length(Task.Supervisor.children(UnirisValidation.TaskSupervisor)) == 2

    processes =
      Task.Supervisor.children(UnirisValidation.TaskSupervisor) |> Enum.map(&Process.info(&1))

    assert {UnirisValidation.DefaultImpl.ContextBuilding, :with_confirmation, _} =
             processes |> List.first() |> get_in([:dictionary, :"$initial_call"])

    assert {UnirisValidation.DefaultImpl.ProofOfWork, :run, _} =
             processes |> Enum.at(1) |> get_in([:dictionary, :"$initial_call"])
  end

  test "start_link/1 should receive transaction context building once done and data should be updated with previous chain downloaded, unspent outputs confirmed and storage nodes involved" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
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
    |> stub(:node_info, fn _ ->
      %Node{
        last_public_key: "node_key1",
        first_public_key: "node_key1",
        network_patch: "AF0",
        ip: "88.100.0.10",
        port: 3000,
        geo_patch: "AAA",
        average_availability: 1,
        availability: 1
      }
    end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:ok, previous_chain}, {:ok, unspent_outputs}]}

        {:get_transaction, _} ->
          {:ok, List.first(unspent_outputs)}

        {:get_proof_of_integrity, _} ->
          {:ok, List.first(previous_chain).validation_stamp.proof_of_integrity}

        {:add_context, _, _, _, _} ->
          :ok
      end
    end)

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: "coordinator_key",
          last_public_key: "coordinator_key",
          ip: '127.0.0.1',
          port: 3000,
          availability: 1,
          geo_patch: "ADA",
          average_availability: 1
        },
        %Node{
          first_public_key: "validator_key",
          last_public_key: "validator_key",
          ip: '88.20.50.1',
          port: 3000,
          availability: 1,
          geo_patch: "AFC",
          average_availability: 1
        }
      ]
    end)
    |> stub(:storage_nodes, fn addr, _, _, _ ->
      if addr == List.first(previous_chain).address do
        [
          %Node{
            last_public_key: "storage_node1",
            first_public_key: "storage_node1",
            geo_patch: "FAC",
            network_patch: "FAA",
            ip: "127.0.0.1",
            port: 3000,
            average_availability: 1,
            availability: 1
          },
          %Node{
            last_public_key: "storage_node2",
            first_public_key: "storage_node2",
            geo_patch: "FAC",
            network_patch: "FAA",
            ip: "127.0.0.1",
            port: 3000,
            average_availability: 1,
            availability: 1
          }
        ]
      else
        [
          %Node{
            last_public_key: "storage_node3",
            first_public_key: "storage_node3",
            geo_patch: "FAC",
            network_patch: "FAA",
            ip: "127.0.0.1",
            port: 3000,
            average_availability: 1,
            availability: 1
          }
        ]
      end
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: ["coordinator_key", "validator_key"]
      )

    Process.sleep(200)

    {_, data} = :sys.get_state(pid)
    %{previous_chain: chain, unspent_outputs: utxo, previous_storage_nodes: nodes} = data
    assert chain == previous_chain
    assert utxo == unspent_outputs

    assert Enum.map(nodes, & &1.last_public_key) == [
             "storage_node1",
             "storage_node2",
             "storage_node3"
           ]
  end

  test "add_context_view/4 should add validation node as confirmed node, previous storage nodes and update validation and storage node views" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    pub = Crypto.last_node_public_key()

    MockNetwork
    |> stub(:node_info, fn _ ->
      %Node{
        last_public_key: "node_key1",
        first_public_key: "node_key1",
        network_patch: "AF0",
        ip: "88.100.0.10",
        port: 3000,
        geo_patch: "AAA",
        average_availability: 1,
        availability: 1
      }
    end)
    |> stub(:origin_public_keys, fn -> [] end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:error, :transaction_chain_not_exists}, {:error, :unspent_outputs_not_exists}]}

        {:add_context, _, _, _, _} ->
          :ok
      end
    end)

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          first_public_key: pub,
          last_public_key: pub,
          ip: '127.0.0.1',
          port: 3000,
          availability: 1,
          geo_patch: "ADA",
          average_availability: 1
        },
        %Node{
          first_public_key: "validator_key2",
          last_public_key: "validator_key2",
          ip: '88.20.50.1',
          port: 3000,
          availability: 1,
          geo_patch: "AFC",
          average_availability: 1
        },
        %Node{
          first_public_key: "validator_key3",
          last_public_key: "validator_key3",
          ip: '88.20.50.1',
          port: 3000,
          availability: 1,
          geo_patch: "AFC",
          average_availability: 1
        }
      ]
    end)
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node1",
          first_public_key: "storage_node1",
          geo_patch: "FAC",
          network_patch: "FAA",
          ip: "127.0.0.1",
          port: 3000,
          average_availability: 1,
          availability: 1
        },
        %Node{
          last_public_key: "storage_node2",
          first_public_key: "storage_node2",
          geo_patch: "FAC",
          network_patch: "FAA",
          ip: "127.0.0.1",
          port: 3000,
          average_availability: 1,
          availability: 1
        }
      ]
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: [pub, "validator_key2", "validator_key3"]
      )

    Process.sleep(200)

    Mining.add_context(
      tx.address,
      "validator_key2",
      ["key10", "key23"],
      <<1::1, 1::1>>,
      <<1::1, 1::1>>
    )

    {_,
     %{
       validation_nodes_view: validation_node_view,
       storage_nodes_view: storage_nodes_view,
       confirm_validation_nodes: confirm_validation_nodes,
       previous_storage_nodes: previous_storage_nodes
     }} = :sys.get_state(pid)

    assert confirm_validation_nodes == ["validator_key2"]
    assert BinarySequence.extract(validation_node_view) == [1, 1]
    assert BinarySequence.extract(storage_nodes_view) == [1, 1]
    assert previous_storage_nodes == ["key10", "key23"]
  end

  test "add_context_view/4 should state as waiting cross validation stamps when add enough validation context and create validation stamp with sending" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }
    me  = self()

    MockNetwork
    |> stub(:node_info, fn _ ->
       %Node{
         first_public_key: "node_key1",
         last_public_key: "node_key1",
         network_patch: "110",
         availability: 1,
         average_availability: 1,
         geo_patch: "",
         ip: "",
         port: 3000
       }
    end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:origin_public_keys, fn -> [] end)
    |> stub(:send_message, fn _, msg ->
      
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:error, :transaction_chain_not_exists}, {:error, :unspent_outputs_not_exists}]}

        {:add_context, _, _, _, _} ->
          :ok

        [{:cross_validate, _, stamp}, {:set_replication_tree, _, tree}] ->
          send(me, {:stamp, stamp})
          send(me, {:tree, tree})
      end
    end)
    pub = UnirisCrypto.last_node_public_key()

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: pub,
          first_public_key: pub,
          ip: '127.0.0.1',
          port: 3000,
          geo_patch: 'ADA',
          average_availability: 1,
          availability: 1,
          network_patch: "ADA"
        },
        %Node{
          last_public_key: "validator_key2",
          first_public_key: "validator_key2",
          ip: '127.0.0.1',
          port: 3000,
          geo_patch: 'ADA',
          average_availability: 1,
          availability: 1,
          network_patch: "DFD"
        },
        %Node{
          last_public_key: "validator_key3",
          first_public_key: "validator_key3",
          ip: '127.0.0.1',
          port: 3000,
          geo_patch: 'ADA',
          average_availability: 1,
          availability: 1,
          network_patch: "ABD"
        }
      ]
    end)
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node_key1",
          first_public_key: "storage_node_key1",
          network_patch: "001",
          availability: 1,
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        },
        %Node{
          last_public_key: "storage_node_key2",
          first_public_key: "storage_node_key2",
          network_patch: "D15",
          availability: 1,
          geo_patch: "AAA",
          ip: "",
          port: 3000,
          average_availability: 1
        }
      ]
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: [pub, "validator_key2", "validator_key3"]
      )

    Process.sleep(200)

    Mining.add_context(
      tx.address,
      "validator_key2",
      ["key10", "key23"],
      <<1::1, 1::1>>,
      <<1::1, 1::1>>
    )

    Mining.add_context(
      tx.address,
      "validator_key3",
      ["key3", "key5"],
      <<0::1, 1::1>>,
      <<0::1, 1::1>>
    )

    {state,
     %{
       validation_nodes_view: validation_node_view,
       storage_nodes_view: storage_nodes_view,
       confirm_validation_nodes: confirm_validation_nodes,
       previous_storage_nodes: previous_storage_nodes
     }} = :sys.get_state(pid)

    assert state == :waiting_cross_validation_stamps
    assert confirm_validation_nodes == ["validator_key2", "validator_key3"]
    assert BinarySequence.extract(validation_node_view) == [1, 1]
    assert BinarySequence.extract(storage_nodes_view) == [1, 1]
    assert previous_storage_nodes == ["key10", "key23", "key3", "key5"]

    assert_received {:stamp, %ValidationStamp{}}

    receive do
      {:tree, replication_tree} ->
        assert Enum.all?(replication_tree, fn replicas ->
                 is_bitstring(replicas) and bit_size(replicas) == 2
               end)
    end
  end

  test "cross_validate/2 should state as waiting cross validation stamp with verificiation of the stamp with notification" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    me = self()

    MockNetwork
    |> stub(:node_info, fn _ ->
      %Node{
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        network_patch: "110",
        availability: 1,
        geo_patch: "AAA",
        ip: "",
        port: 3000,
        average_availability: 1
      }
    end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:origin_public_keys, fn -> [] end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:error, :transaction_chain_not_exists}, {:error, :unspent_outputs_not_exists}]}

        {:add_context, _addr, _previous_nodes, _, _} ->
          :ok

        {:cross_validation_done, _, {_, _inconsistencies}} ->
          send(me, :cross_validation_done)
      end
    end)

    validation_nodes = [
      %Node{
        last_public_key: Crypto.generate_random_keypair(),
        first_public_key: Crypto.generate_random_keypair(),
        ip: '127.0.0.1',
        port: 3000,
        geo_patch: 'ADA',
        average_availability: 1,
        availability: 1,
        network_patch: "ADA"
      },
      %Node{
        last_public_key: Crypto.generate_random_keypair(),
        first_public_key: Crypto.generate_random_keypair(),
        ip: '127.0.0.1',
        port: 3000,
        geo_patch: 'ADA',
        average_availability: 1,
        availability: 1,
        network_patch: "DFD"
      },
      %Node{
        last_public_key: Crypto.generate_random_keypair(),
        first_public_key: Crypto.generate_random_keypair(),
        ip: '127.0.0.1',
        port: 3000,
        geo_patch: 'ADA',
        average_availability: 1,
        availability: 1,
        network_patch: "ABD"
      }
    ]

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ -> validation_nodes end)
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node_key1",
          first_public_key: "storage_node_key1",
          network_patch: "001",
          availability: 1,
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        },
        %Node{
          last_public_key: "storage_node_key2",
          first_public_key: "storage_node_key2",
          network_patch: "AD0",
          availability: 1,
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        }
      ]
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
      )

    Process.sleep(200)

    Mining.cross_validate(tx.address, %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      ledger_movements: %LedgerMovements{uco: %UTXO{previous: %{from: [], amount: 0}, next: 0}},
      node_movements: %NodeMovements{fee: 100, rewards: []},
      signature: ""
    })

    assert {:waiting_cross_validation_stamps,
            %{
              cross_validation_stamps: [
                {_,
                 {_,
                  [
                    :invalid_signature,
                    :invalid_proof_of_integrity,
                    :invalid_fee,
                    :invalid_ledger_movements,
                    :invalid_rewarded_nodes
                  ]}}
              ]
            }} = :sys.get_state(pid)

    assert_received :cross_validation_done
  end

  test "add_cross_validation_stamp/2 should add cross validation stamp to the state and start replication when the atomic commitment is reached" do
    tx = %Transaction{
      address:
        <<0, 244, 145, 127, 161, 241, 33, 162, 253, 228, 223, 233, 125, 143, 71, 189, 178, 226,
          124, 57, 18, 0, 115, 106, 182, 71, 149, 191, 76, 168, 248, 14, 164>>,
      data: %{},
      previous_public_key:
        <<0, 110, 226, 20, 197, 55, 224, 165, 95, 201, 111, 210, 50, 138, 25, 142, 130, 140, 51,
          143, 208, 228, 230, 150, 84, 161, 157, 32, 42, 55, 118, 226, 12>>,
      previous_signature:
        <<141, 38, 35, 252, 145, 124, 224, 234, 52, 113, 147, 7, 254, 45, 155, 16, 93, 218, 167,
          254, 192, 171, 72, 45, 35, 228, 190, 53, 99, 157, 186, 69, 123, 129, 107, 234, 129, 135,
          115, 243, 177, 225, 166, 248, 247, 88, 173, 221, 239, 60, 159, 22, 209, 223, 139, 253,
          6, 210, 81, 143, 0, 118, 222, 15>>,
      timestamp: 1_578_931_642,
      type: :transfer,
      origin_signature: ""
    }

    pub = Crypto.last_node_public_key()

    me = self()

    MockNetwork
    |> stub(:node_info, fn _ ->
      %Node{
        first_public_key: "node_key1",
        last_public_key: "node_key1",
        network_patch: "110",
        availability: 1,
        ip: "",
        port: 3000,
        average_availability: 1,
        geo_patch: "AAA"
     }
    end)
    |> stub(:daily_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:list_nodes, fn -> [%{last_public_key: "node_key2"}] end)
    |> stub(:storage_nonce, fn -> :crypto.strong_rand_bytes(32) end)
    |> stub(:origin_public_keys, fn -> [] end)
    |> stub(:send_message, fn _, msg ->
      case msg do
        [{:get_transaction_chain, _}, {:get_unspent_outputs, _}] ->
          {:ok, [{:error, :transaction_chain_not_exists}, {:error, :unspent_outputs_not_exists}]}

        {:add_context, _, _, _, _} ->
          :ok

        {:cross_validation_done, address, stamp} ->
          Mining.add_cross_validation_stamp(address, stamp, pub)

        {:replicate_transaction, tx} ->
          send(me, {:replicate, tx})
      end
    end)

    validation_nodes = [
      %Node{
        last_public_key: Crypto.generate_random_keypair(),
        first_public_key: Crypto.generate_random_keypair(),
        ip: '127.0.0.1',
        port: 3000,
        geo_patch: 'ADA',
        average_availability: 1,
        availability: 1,
        network_patch: "ADA"
      },
      %Node{
        last_public_key: pub,
        first_public_key: pub,
        ip: '127.0.0.1',
        port: 3000,
        geo_patch: 'ADA',
        average_availability: 1,
        availability: 1,
        network_patch: "DFD"
      },
      %Node{
        last_public_key: Crypto.generate_random_keypair(),
        first_public_key: Crypto.generate_random_keypair(),
        ip: '127.0.0.1',
        port: 3000,
        geo_patch: 'ADA',
        average_availability: 1,
        availability: 1,
        network_patch: "ABD"
      }
    ]

    MockElection
    |> stub(:validation_nodes, fn _, _, _, _ -> validation_nodes end)
    |> stub(:storage_nodes, fn _, _, _, _ ->
      [
        %Node{
          last_public_key: "storage_node_key1",
          first_public_key: "storage_node_key1",
          network_patch: "001",
          availability: 1,
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        },
        %Node{
          last_public_key: "storage_node_key2",
          first_public_key: "storage_node_key2",
          network_patch: "AD0",
          availability: 1,
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        },
        %Node{
          last_public_key: "storage_node_key3",
          first_public_key: "storage_node_key3",
          network_patch: "AD0",
          availability: 1,
          ip: "",
          port: 3000,
          average_availability: 1,
          geo_patch: "AAA"
        },

      ]
    end)

    {:ok, pid} =
      Mining.start_link(
        transaction: tx,
        welcome_node_public_key: "key1",
        validation_node_public_keys: Enum.map(validation_nodes, & &1.last_public_key)
      )

    Process.sleep(200)

    Mining.set_replication_tree(tx.address, [
      <<0::size(3)>>,
      <<5::size(3)>>,
      <<0::size(3)>>
    ])

    Mining.cross_validate(tx.address, %ValidationStamp{
      proof_of_work: "",
      proof_of_integrity: "",
      ledger_movements: %LedgerMovements{uco: %UTXO{previous: %{from: [], amount: 0}, next: 0}},
      node_movements: %NodeMovements{fee: 100, rewards: []},
      signature: ""
    })

    Process.sleep(1000)

    {:replication, %{cross_validation_stamps: stamps}} = :sys.get_state(pid)
    assert length(stamps) == 2

    receive do
      {:replicate, tx} ->
        assert match?(%ValidationStamp{}, tx.validation_stamp)
        assert length(tx.cross_validation_stamps) == 2
    end
  end
end
