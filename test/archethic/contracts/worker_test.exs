defmodule Archethic.Contracts.WorkerTest do
  use ArchethicCase

  alias Archethic.Account

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConstants, as: Constants

  alias Archethic.Contracts.Interpreter

  alias Archethic.Contracts.Worker

  alias Archethic.ContractRegistry

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.PubSub

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    me = self()

    MockClient
    |> stub(:send_message, fn _, %StartMining{transaction: tx}, _ ->
      send(me, {:transaction_sent, tx})
      {:ok, %Ok{}}
    end)

    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    {pub, _} = Crypto.derive_keypair(transaction_seed, 1)
    next_address = Crypto.derive_address(pub)

    secret = Crypto.aes_encrypt(transaction_seed, aes_key)
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    constants =
      %Transaction{
        address: "@SC1",
        data: %TransactionData{
          content: "",
          ownerships: [
            %Ownership{
              secret: secret,
              authorized_keys: %{
                storage_nonce_public_key => Crypto.ec_encrypt(aes_key, storage_nonce_public_key)
              }
            }
          ]
        },
        previous_public_key:
          transaction_seed
          |> Crypto.derive_keypair(0)
          |> elem(0),
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }
      |> Constants.from_transaction()

    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    Account.MemTables.UCOLedger.add_unspent_output(
      "@SC1",
      %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          from: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          amount: 100_000_000_000,
          type: :UCO,
          timestamp: timestamp
        },
        protocol_version: 1
      }
    )

    expected_tx = %Transaction{
      address: next_address,
      type: :transfer,
      data: %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %Transfer{
                to:
                  <<127, 102, 97, 172, 226, 130, 249, 71, 172, 162, 239, 148, 125, 1, 189, 220,
                    144, 198, 95, 9, 238, 130, 139, 218, 222, 46, 62, 212, 37, 132, 112, 179>>,
                amount: 1_040_000_000
              }
            ]
          }
        }
      }
    }

    {:ok, %{constants: constants, expected_tx: expected_tx}}
  end

  describe "start_link/1" do
    test "should spawn a process accessible by its address", %{constants: constants} do
      contract = %Contract{constants: %Constants{contract: constants}}
      {:ok, pid} = Worker.start_link(contract)
      assert Process.alive?(pid)
      %{contract: ^contract} = :sys.get_state(pid)

      assert [{^pid, _}] = Registry.lookup(ContractRegistry, "@SC1")
    end

    test "should schedule a timer for a an datetime trigger", %{
      constants: constants,
      expected_tx: expected_tx
    } do
      code = """
      condition inherit: [
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 1_040_000_000}
      ]

      actions triggered_by: datetime, at: #{DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix()} do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      receive do
        {:transaction_sent, tx} ->
          assert tx.address == expected_tx.address
          assert tx.data.code == code
      after
        3_000 ->
          raise "Timeout"
      end
    end

    test "should schedule a timer for a an interval trigger", %{
      constants: constants,
      expected_tx: expected_tx
    } do
      code = """
      condition inherit: [
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 1_040_000_000}
      ]

      actions triggered_by: interval, at: "* * * * * *" do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract =
        %{
          contract
          | constants: %Constants{contract: Map.put(constants, "code", code)}
        }
        |> Map.update!(:triggers, fn triggers ->
          Enum.map(triggers, fn {{:interval, interval}, code} ->
            {{:interval, interval}, code}
          end)
          |> Enum.into(%{})
        end)

      {:ok, _pid} = Worker.start_link(contract)

      receive do
        {:transaction_sent, tx} ->
          assert tx.address == expected_tx.address
          assert tx.data.code == code

          receive do
            {:transaction_sent, tx} ->
              assert tx.address == expected_tx.address
              assert tx.data.code == code
          after
            100_000 ->
              raise "Timeout"
          end
      after
        100_000 ->
          raise "Timeout"
      end
    end
  end

  describe "execute/2" do
    test "should not execute when no transaction trigger has been defined", %{
      constants: constants = %{"address" => contract_address}
    } do
      contract = %Contract{
        constants: %Constants{contract: constants}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(contract_address, %Transaction{address: "@Alice2"})

      refute_receive {:transaction_sent, _}
    end

    test "should execute a transaction trigger code using an incoming transaction", %{
      constants: constants = %{"address" => contract_address},
      expected_tx: expected_tx
    } do
      code = """
      condition inherit: [
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 1_040_000_000}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(contract_address, %Transaction{
        address: "@Bob3",
        data: %TransactionData{},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      })

      receive do
        {:transaction_sent, tx} ->
          assert tx.address == expected_tx.address
          assert tx.data.ledger == expected_tx.data.ledger
          assert tx.data.code == code
      after
        3_000 ->
          raise "Timeout"
      end
    end

    test "should check transaction condition before to execute a transaction trigger code using an incoming transaction",
         %{
           constants: constants = %{"address" => contract_address},
           expected_tx: expected_tx
         } do
      code = """
      condition transaction: [
        content: regex_match?(\"^Mr.Y|Mr.X{1}$\")
      ]

      condition inherit: [
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 1_040_000_000}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(contract_address, %Transaction{
        address: "@Bob3",
        data: %TransactionData{content: "Mr.X"},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      })

      receive do
        {:transaction_sent, tx} ->
          assert tx.address == expected_tx.address
          assert tx.data.ledger == expected_tx.data.ledger
          assert tx.data.code == code
      after
        3_000 ->
          raise "Timeout"
      end

      Worker.execute(contract_address, %Transaction{
        address: "@Bob3",
        data: %TransactionData{content: "Mr.Z"},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      })

      refute_receive {:transaction_sent, _}
    end

    test "should return a different code if set in the smart contract code", %{
      constants: constants = %{"address" => contract_address},
      expected_tx: expected_tx
    } do
      code = ~s"""
      condition transaction: [
        content: regex_match?("^Mr.Y|Mr.X{1}$")
      ]

      condition inherit: [
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 1_040_000_000}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3", amount: 1_040_000_000
        set_code "
          condition transaction: [
            content: regex_match?(\\"^Mr.Y|Mr.X{1}$\\")
          ]

          condition inherit: [
            uco_transfers: %{ \\"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\\" => 9_200_000_000}
          ]

          actions triggered_by: transaction do
            set_type transfer
            add_uco_transfer to: \\"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\\", amount: 9_200_000_000
          end"
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(contract_address, %Transaction{
        address: "@Bob3",
        data: %TransactionData{content: "Mr.X"},
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      })

      receive do
        {:transaction_sent, tx} ->
          assert tx.address == expected_tx.address
          assert tx.data.ledger == expected_tx.data.ledger
          assert tx.data.code == "
    condition transaction: [
      content: regex_match?(\"^Mr.Y|Mr.X{1}$\")
    ]

    condition inherit: [
      uco_transfers: %{ \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\" => 9_200_000_000}
    ]

    actions triggered_by: transaction do
      set_type transfer
      add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 9_200_000_000
    end"
      after
        3_000 ->
          raise "Timeout"
      end
    end

    test "should execute actions based on an oracle trigger", %{
      constants: constants = %{"address" => _contract_address}
    } do
      code = ~S"""
      condition oracle: [
        content: json_path_extract("$.uco.eur") > 0.20
      ]

      condition inherit: [
        content: regex_match?("(price increased).([0-9]+.[0-9]+)")
      ]

      actions triggered_by: oracle do
        uco_price = json_path_extract(transaction.content, "$.uco.eur")
        set_content "price increased #{uco_price}"
        set_type hosting
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Process.sleep(100)

      oracle_tx = %Transaction{
        address: "@Oracle1",
        type: :oracle,
        data: %TransactionData{
          content: Jason.encode!(%{"uco" => %{"eur" => 0.21}})
        },
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      PubSub.notify_new_transaction("@Oracle1", :oracle, DateTime.utc_now())

      MockDB
      |> expect(:get_transaction, fn "@Oracle1", _, _ -> {:ok, oracle_tx} end)

      receive do
        {:transaction_sent, tx} ->
          assert %Transaction{data: %TransactionData{content: "price increased 0.21"}} = tx
      after
        3_000 ->
          raise "Timeout"
      end
    end

    test "ICO crowdsale", %{
      constants: constants = %{"address" => contract_address}
    } do
      code = """

      # Ensure the next transaction will be a transfer
      condition inherit: [
        type: transfer,
        token_transfers: size() == 1
        # TODO: to provide more security, we should check the destination address is within the previous transaction inputs
      ]

      # Define conditions to accept incoming transactions
      condition transaction: [
        type: transfer,
        uco_transfers: size() > 0
      ]

      actions triggered_by: transaction do
        # Get the amount of uco send to this contract
        amount_send = transaction.uco_transfers[contract.address]

        if amount_send > 0 do
          # Convert UCO to the number of tokens to credit. Each UCO worth 10000 token
          token_to_credit = amount_send * 10000

          # Send the new transaction
          set_type transfer
          add_token_transfer to: transaction.address, token_address: contract.address, amount: token_to_credit
        end
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(contract_address, %Transaction{
        address: "@Bob3",
        type: :transfer,
        data: %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{to: contract_address, amount: 100_000_000}
              ]
            }
          },
          recipients: [contract_address]
        },
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      })

      receive do
        {:transaction_sent,
         %Transaction{
           data: %TransactionData{
             ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
           }
         }} ->
          assert [
                   %TokenTransfer{
                     amount: 100_000_000 * 10_000,
                     to: "@Bob3",
                     token_address: "@SC1",
                     token_id: 0
                   }
                 ] == token_transfers
      after
        3_000 ->
          raise "Timeout"
      end
    end
  end
end
