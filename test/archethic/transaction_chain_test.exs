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
  alias Archethic.P2P.Message.Error

  alias Archethic.TransactionFactory
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
          {:ok, %Error{}}
      end)

      assert {:ok, %Transaction{}} =
               TransactionChain.fetch_transaction("Alice1", nodes, search_mode: :remote)
    end

    test "should resolve conflict with acceptance resolver" do
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

      tx = TransactionFactory.create_valid_transaction([])

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransaction{address: _}, _ ->
          {:ok, tx}

        %Node{port: 3001}, %GetTransaction{address: _}, _ ->
          # split
          {:ok,
           put_in(
             tx,
             [Access.key!(:validation_stamp), Access.key!(:timestamp)],
             DateTime.utc_now()
           )}

        %Node{port: 3002}, %GetTransaction{address: _}, _ ->
          # split
          {:ok,
           put_in(
             tx,
             [Access.key!(:validation_stamp), Access.key!(:timestamp)],
             DateTime.utc_now()
           )}
      end)

      assert {:ok, ^tx} =
               TransactionChain.fetch_transaction(tx.address, nodes,
                 search_mode: :remote,
                 acceptance_resolver: fn tx1 ->
                   tx1.validation_stamp.timestamp == tx.validation_stamp.timestamp
                 end
               )
    end
  end

  describe "fetch/3" do
    setup do
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

      %{nodes: nodes}
    end

    test "should get the transaction chain", %{nodes: nodes} do
      address = random_address()

      MockClient
      |> expect(:send_message, fn
        _, %GetTransactionChain{address: ^address}, _ ->
          {:ok, %TransactionList{transactions: [%Transaction{}]}}
      end)

      assert 1 = TransactionChain.fetch(address, nodes) |> Enum.count()
    end

    test "should get transactions from db and remote", %{nodes: nodes} do
      genesis_address = random_address()
      address1 = random_address()
      address2 = random_address()

      MockDB
      |> expect(:get_genesis_address, fn ^address2 -> genesis_address end)
      |> expect(:get_transaction_chain, fn ^address2, _, _ ->
        {[%Transaction{address: address1}], false, nil}
      end)

      MockClient
      |> expect(
        :send_message,
        fn _, %GetTransactionChain{address: _, paging_state: ^address1}, _ ->
          {:ok, %TransactionList{transactions: [%Transaction{address: address2}]}}
        end
      )

      assert [^address1, ^address2] =
               TransactionChain.fetch(address2, nodes) |> Enum.map(& &1.address)
    end

    test "should be able to fetch remote transactions when paging_state is the last stored address",
         %{nodes: nodes} do
      address1 = random_address()
      address2 = random_address()

      MockDB
      |> expect(:transaction_exists?, fn ^address1, :chain -> true end)

      MockClient
      |> stub(
        :send_message,
        fn _, %GetTransactionChain{address: _, paging_state: ^address1}, _ ->
          {:ok, %TransactionList{transactions: [%Transaction{address: address2}]}}
        end
      )

      assert [^address2] =
               TransactionChain.fetch(address1, nodes, paging_state: address1)
               |> Enum.map(& &1.address)
    end

    test "should resolve the longest chain", %{nodes: nodes} do
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

    test "should resolve paging state as a date", %{nodes: nodes} do
      now = DateTime.utc_now()

      genesis_address = random_address()

      chain_addresses = [
        {random_address(), now},
        {random_address(), DateTime.add(now, 2, :second)},
        {random_address(), DateTime.add(now, 4, :second)}
      ]

      [{address1, _date1}, {address2, date2}, {address3, _date3}] = chain_addresses

      MockDB
      |> expect(:get_genesis_address, fn ^address3 -> genesis_address end)
      |> expect(:list_chain_addresses, fn ^genesis_address -> chain_addresses end)
      |> expect(:transaction_exists?, fn ^address1, _ -> true end)
      |> expect(
        :get_transaction_chain,
        fn ^address1, _, [paging_address: ^address1, order: :asc] ->
          {[%Transaction{address: address2}, %Transaction{address: address3}], false, nil}
        end
      )

      assert [^address2, ^address3] =
               TransactionChain.fetch(address3, nodes, paging_state: date2)
               |> Enum.map(& &1.address)
    end

    test "should request other with unresolved paging date", %{nodes: nodes} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      address = random_address()

      MockDB
      |> expect(:get_genesis_address, fn ^address -> address end)

      MockClient
      |> expect(
        :send_message,
        fn _, %GetTransactionChain{address: ^address, paging_state: ^now}, _ ->
          {:ok, %TransactionList{transactions: [%Transaction{address: random_address()}]}}
        end
      )

      assert [%Transaction{}] =
               TransactionChain.fetch(address, nodes, paging_state: now) |> Enum.to_list()
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

      now = DateTime.utc_now()

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
                 timestamp: now
               },
               protocol_version: 1
             }
           ]
         }}
      end)

      assert [%TransactionInput{from: "Alice2", amount: 10, type: :UCO}] =
               TransactionChain.fetch_inputs("Alice1", nodes, now) |> Enum.to_list()
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

  describe "resolve_paging_state/3" do
    setup do
      date = ~U[2024-01-02 11:55:17.153Z]

      genesis_address = random_address()

      chain_addresses = [
        {random_address(), date},
        {random_address(), DateTime.add(date, 2, :second)},
        {random_address(), DateTime.add(date, 4, :second)}
      ]

      MockDB
      |> stub(:get_genesis_address, fn _ -> genesis_address end)
      |> stub(:list_chain_addresses, fn ^genesis_address -> chain_addresses end)

      %{chain_addresses: chain_addresses, genesis_address: genesis_address}
    end

    test "should return paging address", %{
      chain_addresses: chain_addresses
    } do
      [{paging_address, _}, _, {address3, _}] = chain_addresses

      MockDB
      |> expect(:get_genesis_address, 0, fn _ -> :ok end)
      |> expect(:list_chain_addresses, 0, fn _ -> :ok end)

      assert {:ok, paging_address} ==
               TransactionChain.resolve_paging_state(address3, paging_address, :asc)

      assert {:ok, paging_address} ==
               TransactionChain.resolve_paging_state(address3, paging_address, :desc)

      assert {:ok, nil} == TransactionChain.resolve_paging_state(address3, nil, :asc)

      assert {:ok, nil} == TransactionChain.resolve_paging_state(address3, nil, :desc)
    end

    test "should resolve address using from date in asc order", %{
      chain_addresses: chain_addresses
    } do
      [{address1, date1}, {address2, date2}, {address3, date3}] = chain_addresses

      assert {:ok, nil} ==
               TransactionChain.resolve_paging_state(address3, date1, :asc)

      assert {:ok, address1} ==
               TransactionChain.resolve_paging_state(address3, date2, :asc)

      assert {:ok, address2} ==
               TransactionChain.resolve_paging_state(address3, date3, :asc)

      date = DateTime.add(date1, 1, :second)

      assert {:ok, address1} ==
               TransactionChain.resolve_paging_state(address3, date, :asc)
    end

    test "should resolve address using from date in desc order", %{
      chain_addresses: chain_addresses
    } do
      [{_, date1}, {address2, date2}, {address3, date3}] = chain_addresses

      assert {:ok, address2} ==
               TransactionChain.resolve_paging_state(address3, date1, :desc)

      assert {:ok, address3} ==
               TransactionChain.resolve_paging_state(address3, date2, :desc)

      assert {:ok, nil} ==
               TransactionChain.resolve_paging_state(address3, date3, :desc)

      date = DateTime.add(date1, 1, :second)

      assert {:ok, address2} ==
               TransactionChain.resolve_paging_state(address3, date, :desc)
    end

    test "should return address when time is same second but over in millisecond", %{
      chain_addresses: chain_addresses
    } do
      [{address1, _}, {_, date2}, {address3, _}] = chain_addresses

      date = DateTime.truncate(date2, :second)

      assert DateTime.compare(date, date2) == :lt

      assert {:ok, address1} ==
               TransactionChain.resolve_paging_state(address3, date, :asc)

      assert {:ok, address3} ==
               TransactionChain.resolve_paging_state(address3, date, :desc)
    end

    test "should return {:error, :not_in_local} when node does not know genesis_address", %{
      chain_addresses: chain_addresses
    } do
      [_, _, {address3, date3}] = chain_addresses

      MockDB
      |> expect(:get_genesis_address, 2, fn ^address3 -> address3 end)

      assert {:error, :not_in_local} ==
               TransactionChain.resolve_paging_state(address3, date3, :asc)

      assert {:error, :not_in_local} ==
               TransactionChain.resolve_paging_state(address3, date3, :desc)
    end

    test "should return {:error, :not_exists} if requested from is out of chain range", %{
      chain_addresses: chain_addresses
    } do
      [{_, date1}, _, {address3, date3}] = chain_addresses

      date = DateTime.add(date3, 1, :second)

      assert {:error, :not_exists} = TransactionChain.resolve_paging_state(address3, date, :asc)

      date = DateTime.add(date1, -1, :second)

      assert {:error, :not_exists} = TransactionChain.resolve_paging_state(address3, date, :desc)
    end
  end
end
