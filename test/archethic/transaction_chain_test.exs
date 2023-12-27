defmodule Archethic.TransactionChainTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetFirstTransactionAddress
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.NotFound

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  doctest TransactionChain

  import Mox
  import ArchethicCase

  describe "fetch_last_address/1 should retrieve the last address for a chain" do
    test "when not conflicts" do
      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:11:29Z]}, _ ->
          {:ok, %LastTransactionAddress{address: "@Alice1", timestamp: DateTime.utc_now()}}

        _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:12:29Z]}, _ ->
          {:ok,
           %LastTransactionAddress{
             address: "@Alice2",
             timestamp: DateTime.utc_now() |> DateTime.add(2)
           }}
      end)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: ~U[2021-03-25 15:11:29Z]
      })

      nodes = P2P.authorized_and_available_nodes()

      assert {:ok, "@Alice1"} =
               TransactionChain.fetch_last_address("@Alice1", nodes,
                 timestamp: ~U[2021-03-25 15:11:29Z]
               )

      assert {:ok, "@Alice2"} =
               TransactionChain.fetch_last_address("@Alice1", nodes,
                 timestamp: ~U[2021-03-25 15:12:29Z]
               )
    end

    test "with conflicts" do
      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: "@Alice1", timestamp: DateTime.utc_now()}}

        %Node{port: 3001}, %GetLastTransactionAddress{}, _ ->
          {:ok,
           %LastTransactionAddress{
             address: "@Alice2",
             timestamp: DateTime.utc_now() |> DateTime.add(2)
           }}
      end)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3001,
        first_public_key: :crypto.strong_rand_bytes(34),
        last_public_key: :crypto.strong_rand_bytes(34),
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      nodes = P2P.authorized_and_available_nodes()

      assert {:ok, "@Alice2"} = TransactionChain.fetch_last_address("@Alice1", nodes)
    end

    test "should ask all the elected nodes with a specific acceptance resolver" do
      address = random_address()
      now = DateTime.utc_now()

      MockClient
      |> expect(:send_message, 200, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: address, timestamp: now}}
      end)

      Enum.each(1..200, fn i ->
        P2P.add_and_connect_node(%Node{
          ip: {127, 0, 0, 1},
          port: 3000 + i,
          first_public_key: random_public_key(),
          last_public_key: random_public_key(),
          available?: true,
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.add(now, -1, :day)
        })
      end)

      nodes = P2P.authorized_and_available_nodes()

      acceptance_resolver = fn %LastTransactionAddress{timestamp: remote_last_address_timestamp} ->
        now < remote_last_address_timestamp
      end

      assert {:error, :acceptance_failed} =
               TransactionChain.fetch_last_address(address, nodes,
                 timestamp: now,
                 acceptance_resolver: acceptance_resolver
               )
    end

    test "should ask only a few nodes if they have a more recent value" do
      address = random_address()
      latest_address = random_address()
      now = DateTime.utc_now()

      consistency_level = 8

      MockClient
      |> expect(:send_message, consistency_level, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok,
         %LastTransactionAddress{
           address: latest_address,
           timestamp: DateTime.add(now, 1, :minute)
         }}
      end)

      Enum.each(1..200, fn i ->
        P2P.add_and_connect_node(%Node{
          ip: {127, 0, 0, 1},
          port: 3000 + i,
          first_public_key: random_public_key(),
          last_public_key: random_public_key(),
          available?: true,
          geo_patch: "AAA",
          network_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.add(now, -1, :day)
        })
      end)

      nodes = P2P.authorized_and_available_nodes()

      acceptance_resolver = fn %LastTransactionAddress{timestamp: remote_last_address_timestamp} ->
        now < remote_last_address_timestamp
      end

      assert {:ok, ^latest_address} =
               TransactionChain.fetch_last_address(address, nodes,
                 timestamp: now,
                 consistency_level: consistency_level,
                 acceptance_resolver: acceptance_resolver
               )
    end
  end

  describe "fetch_transaction/2" do
    test "should get the transaction from DB" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockDB
      |> expect(:get_transaction, fn "Alice1", _, _ -> {:ok, %Transaction{}} end)

      assert {:ok, %Transaction{}} = TransactionChain.fetch_transaction("Alice1", nodes)
    end

    test "should resolve conflict and get tx if one tx is returned" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransaction{address: _}, _ ->
          {:ok, %NotFound{}}

        %Node{port: 3001}, %GetTransaction{address: _}, _ ->
          {:ok, %Transaction{}}

        %Node{port: 3002}, %GetTransaction{address: _}, _ ->
          {:ok, %NotFound{}}
      end)

      assert {:ok, %Transaction{}} =
               TransactionChain.fetch_transaction("Alice1", nodes, search_mode: :remote)
    end
  end

  describe "fetch/3" do
    test "should get the transaction chain" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransactionChain{address: _}, _ ->
          {:ok,
           %TransactionList{
             transactions: [
               %Transaction{}
             ]
           }}
      end)

      assert 1 = TransactionChain.fetch("Alice1", nodes) |> Enum.count()
    end

    test "should get transactions from db and remote" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockDB
      |> expect(:get_genesis_address, fn _ -> "Alice0" end)
      |> expect(:get_transaction_chain, fn _, _, _ ->
        {[%Transaction{address: "Alice1"}], false, nil}
      end)

      MockClient
      |> expect(
        :send_message,
        fn _, %GetTransactionChain{address: _, paging_state: "Alice1"}, _ ->
          {:ok, %TransactionList{transactions: [%Transaction{address: "Alice2"}]}}
        end
      )

      assert ["Alice1", "Alice2"] =
               TransactionChain.fetch("Alice2", nodes) |> Enum.map(& &1.address)
    end

    test "should resolve the longest chain" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      validation_stamp = %ValidationStamp{timestamp: DateTime.utc_now()}

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransactionChain{address: _}, _ ->
          {:ok, %TransactionList{}}

        %Node{port: 3001}, %GetTransactionChain{address: _}, _ ->
          {:ok,
           %TransactionList{
             transactions: [
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp}
             ],
             more?: false
           }}

        %Node{port: 3002}, %GetTransactionChain{address: _}, _ ->
          {:ok,
           %TransactionList{
             transactions: [
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp},
               %Transaction{validation_stamp: validation_stamp}
             ],
             more?: false
           }}

        _, %GetTransactionChainLength{}, _ ->
          %TransactionChainLength{length: 1}
      end)

      assert 5 = TransactionChain.fetch("Alice1", nodes) |> Enum.count()
    end
  end

  describe "fetch_inputs/5" do
    test "should get the inputs" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionInputs{address: _}, _ ->
        {:ok,
         %TransactionInputList{
           inputs: [
             %VersionedTransactionInput{
               input: %TransactionInput{
                 from: "Alice2",
                 amount: 10,
                 type: :UCO,
                 spent?: false,
                 timestamp: DateTime.utc_now()
               },
               protocol_version: 1
             }
           ]
         }}
      end)

      assert [%TransactionInput{from: "Alice2", amount: 10, type: :UCO}] =
               TransactionChain.fetch_inputs("Alice1", nodes, DateTime.utc_now())
               |> Enum.to_list()
    end

    test "should resolve the longest inputs when conflicts" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransactionInputs{address: _}, _ ->
          {:ok, %TransactionInputList{inputs: []}}

        %Node{port: 3001}, %GetTransactionInputs{address: _}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "Alice2",
                   amount: 10,
                   type: :UCO,
                   timestamp: DateTime.utc_now()
                 },
                 protocol_version: 1
               }
             ]
           }}

        %Node{port: 3002}, %GetTransactionInputs{address: _}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "Alice2",
                   amount: 10,
                   type: :UCO,
                   timestamp: DateTime.utc_now()
                 },
                 protocol_version: 1
               },
               %VersionedTransactionInput{
                 input: %TransactionInput{
                   from: "Bob3",
                   amount: 2,
                   type: :UCO,
                   timestamp: DateTime.utc_now()
                 },
                 protocol_version: 1
               }
             ]
           }}
      end)

      assert [%TransactionInput{from: "Alice2"}, %TransactionInput{from: "Bob3"}] =
               TransactionChain.fetch_inputs("Alice1", nodes, DateTime.utc_now())
               |> Enum.to_list()
    end
  end

  describe "fetch_unspent_outputs_remotely/2" do
    test "should get the utxos" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      MockClient
      |> stub(:send_message, fn _, %GetUnspentOutputs{address: _}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: [
             %VersionedUnspentOutput{
               unspent_output: %UnspentOutput{
                 from: "Alice2",
                 amount: 10,
                 type: :UCO,
                 timestamp: timestamp
               },
               protocol_version: 1
             }
           ]
         }}
      end)

      assert [%UnspentOutput{from: "Alice2", amount: 10, type: :UCO, timestamp: ^timestamp}] =
               TransactionChain.fetch_unspent_outputs("Alice1", nodes) |> Enum.to_list()
    end

    test "should resolve the longest utxos when conflicts" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)
      timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetUnspentOutputs{address: _}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        %Node{port: 3001}, %GetUnspentOutputs{address: _}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "Alice2",
                   amount: 10,
                   type: :UCO,
                   timestamp: timestamp
                 },
                 protocol_version: 1
               }
             ]
           }}

        %Node{port: 3002}, %GetUnspentOutputs{address: _}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "Alice2",
                   amount: 10,
                   type: :UCO,
                   timestamp: timestamp
                 },
                 protocol_version: 1
               },
               %VersionedUnspentOutput{
                 unspent_output: %UnspentOutput{
                   from: "Bob3",
                   amount: 2,
                   type: :UCO,
                   timestamp: timestamp
                 },
                 protocol_version: 1
               }
             ]
           }}
      end)

      assert [
               %UnspentOutput{from: "Alice2", timestamp: ^timestamp},
               %UnspentOutput{from: "Bob3", timestamp: ^timestamp}
             ] = TransactionChain.fetch_unspent_outputs("Alice1", nodes) |> Enum.to_list()
    end
  end

  describe "fetch_size/2" do
    test "should get the transaction chain length" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionChainLength{address: _}, _ ->
        {:ok, %TransactionChainLength{length: 1}}
      end)

      assert {:ok, 1} = TransactionChain.fetch_size("Alice1", nodes)
    end

    test "should resolve the longest transaction chain when conflicts" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          available?: true
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002,
          available?: true
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransactionChainLength{address: _}, _ ->
          {:ok, %TransactionChainLength{length: 1}}

        %Node{port: 3001}, %GetTransactionChainLength{address: _}, _ ->
          {:ok, %TransactionChainLength{length: 2}}

        %Node{port: 3002}, %GetTransactionChainLength{address: _}, _ ->
          {:ok, %TransactionChainLength{length: 1}}
      end)

      assert {:ok, 2} = TransactionChain.fetch_size("Alice1", nodes)
    end
  end

  describe "fetch_first_address_remotely/2" do
    setup do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true,
          authorized?: true,
          geo_patch: "AAA",
          authorization_date: DateTime.utc_now()
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.utc_now()
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          geo_patch: "AAA",
          ip: {127, 0, 0, 1},
          port: 3002,
          authorized?: true,
          authorization_date: DateTime.utc_now()
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      %{nodes: nodes}
    end

    test "when first txn exists", %{nodes: nodes} do
      MockClient
      |> stub(:send_message, fn
        _, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr1", timestamp: DateTime.utc_now()}}
      end)

      assert {:ok, "addr1"} = TransactionChain.fetch_first_transaction_address("addr2", nodes)
    end

    test "when asked from genesis address", %{nodes: nodes} do
      node1 = Enum.at(nodes, 0)
      node2 = Enum.at(nodes, 1)
      node3 = Enum.at(nodes, 2)

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetFirstTransactionAddress{address: "addr0"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr0", timestamp: DateTime.utc_now()}}

        ^node2, %GetFirstTransactionAddress{address: "addr0"}, _ ->
          %Archethic.P2P.Message.NotFound{}

        ^node3, %GetFirstTransactionAddress{address: "addr0"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr0", timestamp: DateTime.utc_now()}}

        _, _, _ ->
          {:ok, %NotFound{}}
      end)

      assert {:ok, "addr0"} = TransactionChain.fetch_first_transaction_address("addr0", nodes)

      assert {:error, :does_not_exist} =
               TransactionChain.fetch_first_transaction_address(
                 "not_existing_address",
                 nodes
               )
    end

    test "should resolve conflict when one node has a forked chain", %{nodes: nodes} do
      node1 = Enum.at(nodes, 0)
      node2 = Enum.at(nodes, 1)
      node3 = Enum.at(nodes, 2)

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr1", timestamp: ~U[2023-01-01 00:00:00Z]}}

        # this one missed a transaction (and created a fork chain somehow)
        ^node2, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr10", timestamp: ~U[2023-01-01 01:00:00Z]}}

        ^node3, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr1", timestamp: ~U[2023-01-01 00:00:00Z]}}
      end)

      assert {:ok, "addr1"} = TransactionChain.fetch_first_transaction_address("addr2", nodes)
    end

    test "should resolve conflict when one node does not have the transaction", %{nodes: nodes} do
      node1 = Enum.at(nodes, 0)
      node2 = Enum.at(nodes, 1)
      node3 = Enum.at(nodes, 2)

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr1", timestamp: ~U[2023-01-01 00:00:00Z]}}

        # this one missed a transaction
        ^node2, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %NotFound{}}

        ^node3, %GetFirstTransactionAddress{address: "addr2"}, _ ->
          {:ok, %FirstTransactionAddress{address: "addr1", timestamp: ~U[2023-01-01 00:00:00Z]}}
      end)

      assert {:ok, "addr1"} = TransactionChain.fetch_first_transaction_address("addr2", nodes)
    end
  end

  describe "First Tx" do
    setup do
      now = DateTime.utc_now()

      MockDB
      |> stub(:get_genesis_address, fn
        "not_existing_address" ->
          "not_existing_address"

        "addr10" ->
          "addr0"
      end)
      |> stub(:list_chain_addresses, fn
        "not_existing_address" ->
          []

        "addr0" ->
          [
            {"addr1", now |> DateTime.add(-2000)},
            {"addr2", now |> DateTime.add(-1000)},
            {"addr3", now |> DateTime.add(-500)}
          ]
      end)
      |> stub(:get_transaction, fn "addr1", _ ->
        {:ok, %Transaction{address: "addr1"}}
      end)

      %{addr1_timestamp: now |> DateTime.add(-2000)}
    end

    test "get_first_transaction_address/2", %{addr1_timestamp: addr1_timestamp} do
      assert {:ok, {"addr1", ^addr1_timestamp}} =
               TransactionChain.get_first_transaction_address("addr10")

      assert {:error, :transaction_not_exists} =
               TransactionChain.get_first_transaction_address("not_existing_address")
    end
  end

  describe "fetch_genesis_address/2" do
    setup do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000,
          available?: true,
          authorized?: true,
          geo_patch: "AAA",
          authorization_date: DateTime.utc_now()
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001,
          geo_patch: "AAA",
          authorized?: true,
          authorization_date: DateTime.utc_now()
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          geo_patch: "AAA",
          ip: {127, 0, 0, 1},
          port: 3002,
          authorized?: true,
          authorization_date: DateTime.utc_now()
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      %{nodes: nodes}
    end

    test "should work when no conflict", %{nodes: nodes} do
      MockClient
      |> stub(:send_message, fn
        _, %GetGenesisAddress{address: "addr2"}, _ ->
          {:ok, %GenesisAddress{address: "addr1", timestamp: DateTime.utc_now()}}
      end)

      assert {:ok, "addr1"} = TransactionChain.fetch_genesis_address("addr2", nodes)
    end

    test "should resolve conflict when one node has a forked chain", %{nodes: nodes} do
      node1 = Enum.at(nodes, 0)
      node2 = Enum.at(nodes, 1)
      node3 = Enum.at(nodes, 2)

      MockClient
      |> stub(:send_message, fn
        ^node1, %GetGenesisAddress{address: "addr2"}, _ ->
          {:ok, %GenesisAddress{address: "addr1", timestamp: ~U[2023-01-01 00:00:00Z]}}

        # this one missed a transaction (and created a fork chain somehow)
        ^node2, %GetGenesisAddress{address: "addr2"}, _ ->
          {:ok, %GenesisAddress{address: "addr10", timestamp: ~U[2023-01-01 01:00:00Z]}}

        ^node3, %GetGenesisAddress{address: "addr2"}, _ ->
          {:ok, %GenesisAddress{address: "addr1", timestamp: ~U[2023-01-01 00:00:00Z]}}
      end)

      assert {:ok, "addr1"} = TransactionChain.fetch_genesis_address("addr2", nodes)
    end
  end
end
