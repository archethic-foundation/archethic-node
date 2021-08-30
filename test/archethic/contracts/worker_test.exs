defmodule ArchEthic.Contracts.WorkerTest do
  use ArchEthicCase

  alias ArchEthic.Contracts.Contract
  alias ArchEthic.Contracts.Contract.Constants

  alias ArchEthic.Contracts.Interpreter

  alias ArchEthic.Contracts.Worker

  alias ArchEthic.ContractRegistry

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.StartMining
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer

  alias ArchEthic.PubSub

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
    |> stub(:send_message, fn _, %StartMining{transaction: tx} ->
      send(me, {:transaction_sent, tx})
      {:ok, %Ok{}}
    end)

    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    {pub, _} = Crypto.derive_keypair(transaction_seed, 1)
    next_address = Crypto.hash(pub)

    secret = Crypto.aes_encrypt(transaction_seed, aes_key)

    constants = %{
      "address" => "@SC1",
      "authorized_keys" => %{
        Crypto.storage_nonce_public_key() =>
          Crypto.ec_encrypt(aes_key, Crypto.storage_nonce_public_key())
      },
      "secret" => secret,
      "content" => "",
      "uco_transferred" => 0.0,
      "nft_transferred" => 0.0,
      "previous_public_key" => transaction_seed |> Crypto.derive_keypair(0) |> elem(0)
    }

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
                amount: 10.04
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
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04}
      ]

      actions triggered_by: datetime, at: #{DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix()} do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
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
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04}
      ]

      actions triggered_by: interval, at: "* * * * * *" do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
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

          receive do
            {:transaction_sent, tx} ->
              assert tx.address == expected_tx.address
              assert tx.data.code == code
          after
            3_000 ->
              raise "Timeout"
          end
      after
        3_000 ->
          raise "Timeout"
      end
    end
  end

  describe "execute/2" do
    test "should return an error when not transaction trigger has been defined", %{
      constants: constants = %{"address" => contract_address}
    } do
      contract = %Contract{
        constants: %Constants{contract: constants}
      }

      {:ok, _pid} = Worker.start_link(contract)

      assert {:error, :no_transaction_trigger} =
               Worker.execute(contract_address, %Transaction{address: "@Alice2"})

      refute_receive {:transaction_sent, _}
    end

    test "should execute a transaction trigger code using an incoming transaction", %{
      constants: constants = %{"address" => contract_address},
      expected_tx: expected_tx
    } do
      code = """
      condition inherit: [
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      assert :ok =
               Worker.execute(contract_address, %Transaction{
                 address: "@Bob3",
                 data: %TransactionData{}
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
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      assert :ok =
               Worker.execute(contract_address, %Transaction{
                 address: "@Bob3",
                 data: %TransactionData{content: "Mr.X"}
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

      assert {:error, :invalid_condition} =
               Worker.execute(contract_address, %Transaction{
                 address: "@Bob3",
                 data: %TransactionData{content: "Mr.Z"}
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
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04}
      ]

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3", amount: 10.04
        set_code "
          condition transaction: [
            content: regex_match?(\\"^Mr.Y|Mr.X{1}$\\")
          ]

          condition inherit: [
            uco_transfers: %{ \\"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\\" => 9.20}
          ]

          actions triggered_by: transaction do
            set_type transfer
            add_uco_transfer to: \\"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\\", amount: 9.20
          end"
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Map.put(constants, "code", code)}
      }

      {:ok, _pid} = Worker.start_link(contract)

      assert :ok =
               Worker.execute(contract_address, %Transaction{
                 address: "@Bob3",
                 data: %TransactionData{content: "Mr.X"}
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
      uco_transfers: %{ \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\" => 9.20}
    ]

    actions triggered_by: transaction do
      set_type transfer
      add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 9.20
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
        }
      }

      PubSub.notify_new_transaction("@Oracle1", :oracle, DateTime.utc_now())

      MockDB
      |> expect(:get_transaction, fn "@Oracle1", _ -> {:ok, oracle_tx} end)

      receive do
        {:transaction_sent, tx} ->
          assert %Transaction{data: %TransactionData{content: "price increased 0.21"}} = tx
      after
        3_000 ->
          raise "Timeout"
      end
    end
  end
end
