defmodule Archethic.Contracts.WorkerTest do
  use ArchethicCase

  alias Archethic.{Account, Contracts, ContractRegistry, Crypto, P2P}
  alias Archethic.{P2P.Node, PubSub, TransactionChain}

  alias Contracts.{Contract, Interpreter, Worker, ContractConstants}

  alias P2P.Message.{Ok, StartMining}

  alias TransactionChain.{Transaction, TransactionData, Transaction.ValidationStamp}
  alias ValidationStamp.{LedgerOperations.UnspentOutput, LedgerOperations.VersionedUnspentOutput}
  alias TransactionData.{Ledger, Ownership, UCOLedger, UCOLedger.Transfer, TokenLedger}
  alias TransactionData.TokenLedger.Transfer, as: TokenTransfer

  alias Archethic.TransactionChain.TransactionData.Recipient

  import ArchethicCase
  import Mox

  @bob_address <<0::16, :crypto.strong_rand_bytes(32)::binary>>

  def load_send_tx_constraints() do
    setup_before_send_tx()
  end

  setup do
    load_send_tx_constraints()

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
    |> stub(:send_message, fn
      _, %StartMining{transaction: tx}, _ ->
        send(me, {:transaction_sent, tx})
        {:ok, %Ok{}}
    end)

    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    {pub, _} = Crypto.derive_keypair(transaction_seed, 1)
    next_address = Crypto.derive_address(pub)

    secret = Crypto.aes_encrypt(transaction_seed, aes_key)
    storage_nonce_public_key = Crypto.storage_nonce_public_key()

    contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

    constants =
      %Transaction{
        address: contract_address,
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
      |> ContractConstants.from_transaction()

    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    Account.MemTables.UCOLedger.add_unspent_output(
      contract_address,
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

    to = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

    expected_tx = %Transaction{
      address: next_address,
      type: :transfer,
      data: %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %Transfer{
                to: to,
                amount: 1_040_000_000
              }
            ]
          }
        }
      }
    }

    {:ok, %{constants: constants, expected_tx: expected_tx, to: to}}
  end

  describe "start_link/1" do
    test "should spawn a process accessible by its address", %{
      constants: constants = %{"address" => contract_address}
    } do
      contract = %Contract{constants: %ContractConstants{contract: constants}}
      {:ok, pid} = Worker.start_link(contract)
      assert Process.alive?(pid)
      %{contract: ^contract} = :sys.get_state(pid)

      assert [{^pid, _}] = Registry.lookup(ContractRegistry, contract_address)
    end

    test "should schedule a timer for a an datetime trigger", %{
      constants: constants,
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = """
      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      actions triggered_by: datetime, at: #{DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix()} do
        set_type transfer
        add_uco_transfer to: "#{address}", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
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
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = """
      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      actions triggered_by: interval, at: "* * * * * *" do
        set_type transfer
        add_uco_transfer to: "#{address}", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

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
            5000 ->
              raise "Timeout"
          end
      after
        5000 ->
          raise "Timeout"
      end
    end
  end

  describe "execute/2" do
    test "should not execute when no transaction trigger has been defined", %{
      constants: constants = %{"address" => contract_address}
    } do
      contract = %Contract{
        constants: %ContractConstants{contract: constants}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(contract_address, %Transaction{address: "@Alice2"}, %Recipient{
        address: contract_address
      })

      refute_receive {:transaction_sent, _}
    end

    test "should execute a transaction trigger code using an incoming transaction", %{
      constants: constants = %{"address" => contract_address},
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = """
      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      condition transaction: []

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to:  "#{address}", amount: 1_040_000_000
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(
        contract_address,
        %Transaction{
          address: @bob_address,
          data: %TransactionData{},
          validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
        },
        %Recipient{
          address: contract_address
        }
      )

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

    test "should return a different code if set in the smart contract code", %{
      constants: constants = %{"address" => contract_address},
      expected_tx: expected_tx,
      to: to
    } do
      address = Base.encode16(to)

      code = ~s"""
      condition transaction: []

      condition inherit: [
        uco_transfers: %{ "#{address}" => 1_040_000_000}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: "#{address}", amount: 1_040_000_000
        set_code "
          condition transaction: []

          condition inherit: [
            uco_transfers: %{ \\"#{address}\\" => 9_200_000_000}
          ]

          actions triggered_by: transaction do
            set_type transfer
            add_uco_transfer to: \\"#{address}\\", amount: 9_200_000_000
          end"
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(
        contract_address,
        %Transaction{
          address: @bob_address,
          data: %TransactionData{content: "Mr.X"},
          validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
        },
        %Recipient{
          address: contract_address
        }
      )

      receive do
        {:transaction_sent, tx} ->
          assert tx.address == expected_tx.address
          assert tx.data.ledger == expected_tx.data.ledger
          assert tx.data.code == "
    condition transaction: []

    condition inherit: [
      uco_transfers: %{ \"#{address}\" => 9_200_000_000}
    ]

    actions triggered_by: transaction do
      set_type transfer
      add_uco_transfer to: \"#{address}\", amount: 9_200_000_000
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

      oracle_tx = %Transaction{
        address: "@Oracle1",
        type: :oracle,
        data: %TransactionData{
          content: Jason.encode!(%{"uco" => %{"eur" => 0.21}})
        },
        validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
      }

      nss_last_address = "nss_last_address"
      nss_genesis_address = "nss_genesis_address"

      MockDB
      |> stub(:get_last_chain_address, fn ^nss_genesis_address ->
        {nss_last_address, DateTime.utc_now()}
      end)
      |> stub(
        :get_transaction,
        fn
          "@Oracle1", [], :chain ->
            {:ok, oracle_tx}

          ^nss_last_address, [validation_stamp: [:timestamp]], :chain ->
            {:ok,
             %Transaction{
               validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
             }}
        end
      )

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

      {:ok, pid} = Worker.start_link(contract)
      allow(MockDB, self(), pid)
      # Process.sleep(100)

      PubSub.notify_new_transaction("@Oracle1", :oracle, DateTime.utc_now())

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
      # the contract need uco to be executed
      Archethic.Account.MemTables.TokenLedger.add_unspent_output(
        contract_address,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Bob3",
            amount: 100_000_000 * 10_000,
            type: {:token, contract_address, 0},
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
          },
          protocol_version: ArchethicCase.current_protocol_version()
        }
      )

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
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(
        contract_address,
        %Transaction{
          address: @bob_address,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: contract_address, amount: 100_000_000}
                ]
              }
            },
            recipients: [%Recipient{address: contract_address}]
          },
          validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
        },
        %Recipient{address: contract_address}
      )

      receive do
        {:transaction_sent,
         %Transaction{
           data: %TransactionData{
             ledger: %Ledger{token: %TokenLedger{transfers: token_transfers}}
           }
         }} ->
          [
            %TokenTransfer{
              amount: amount,
              to: to,
              token_address: token_address,
              token_id: token_id
            }
          ] = token_transfers

          assert 1 == length(token_transfers)
          assert 100_000_000 * 10_000 == amount
          assert contract_address == token_address
          assert 0 == token_id
          assert @bob_address == to
      after
        3_000 ->
          raise "Timeout"
      end
    end

    test "named action", %{
      constants: constants = %{"address" => contract_address}
    } do
      code = """
      @version 1

      condition triggered_by: transaction, on: vote(candidate), as: []
      actions triggered_by: transaction, on: vote(candidate) do
        Contract.set_content(candidate)
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      Worker.execute(
        contract_address,
        %Transaction{
          address: @bob_address,
          type: :data,
          data: %TransactionData{
            recipients: [
              %Recipient{
                address: contract_address,
                action: "vote",
                args: ["Ms. Smith"]
              }
            ]
          },
          validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
        },
        %Recipient{
          address: contract_address,
          action: "vote",
          args: ["Ms. Smith"]
        }
      )

      receive do
        {:transaction_sent, %Transaction{data: %TransactionData{content: content}}} ->
          assert content == "Ms. Smith"

        _ ->
          assert false
      after
        3_000 ->
          raise "Timeout"
      end
    end

    test "should not crash the worker if contract code crashes", %{
      constants: constants = %{"address" => contract_address}
    } do
      # the contract need uco to be executed
      Archethic.Account.MemTables.TokenLedger.add_unspent_output(
        contract_address,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: "@Bob3",
            amount: 100_000_000 * 10_000,
            type: {:token, contract_address, 0},
            timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
          },
          protocol_version: ArchethicCase.current_protocol_version()
        }
      )

      code = """
      @version 1
      condition triggered_by: transaction, as: []
      actions triggered_by: transaction do
        n = 10 / 0
        Contract.set_content n
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %ContractConstants{contract: Map.put(constants, "code", code)}
      }

      {:ok, worker_pid} = Worker.start_link(contract)

      Worker.execute(
        contract_address,
        %Transaction{
          address: @bob_address,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{to: contract_address, amount: 100_000_000}
                ]
              }
            },
            recipients: [%Recipient{address: contract_address}]
          },
          validation_stamp: %ValidationStamp{timestamp: DateTime.utc_now()}
        },
        %Recipient{
          address: contract_address
        }
      )

      Process.sleep(100)

      assert Process.alive?(worker_pid)
    end
  end
end
