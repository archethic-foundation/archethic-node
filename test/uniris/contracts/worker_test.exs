defmodule Uniris.Contracts.WorkerTest do
  use UnirisCase

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Constants

  alias Uniris.Contracts.Interpreter

  alias Uniris.Contracts.Worker

  alias Uniris.ContractRegistry

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Batcher
  alias Uniris.P2P.Message.BatchRequests
  alias Uniris.P2P.Message.BatchResponses
  alias Uniris.P2P.Message.Ok
  alias Uniris.P2P.Message.StartMining
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer

  import Mox

  setup do
    start_supervised!(Batcher)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      geo_patch: "AAA",
      network_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    me = self()

    MockClient
    |> stub(:send_message, fn
      _, %BatchRequests{requests: [%StartMining{transaction: tx}]}, _ ->
        send(me, {:transaction_sent, tx})
        {:ok, %BatchResponses{responses: [{0, %Ok{}}]}}
    end)

    aes_key = :crypto.strong_rand_bytes(32)
    transaction_seed = :crypto.strong_rand_bytes(32)

    {pub, _} = Crypto.derive_keypair(transaction_seed, 1)
    next_address = Crypto.hash(pub)

    secret = Crypto.aes_encrypt(transaction_seed, aes_key)

    constants = [
      address: "@SC1",
      authorized_keys: %{
        Crypto.storage_nonce_public_key() =>
          Crypto.ec_encrypt(aes_key, Crypto.storage_nonce_public_key())
      },
      secret: secret,
      content: "",
      uco_transferred: 0.0,
      nft_transferred: 0.0
    ]

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
      condition inherit,
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3": 10.04}

      actions triggered_by: datetime, at: #{
        DateTime.utc_now() |> DateTime.add(1) |> DateTime.to_unix()
      } do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Keyword.put(constants, :code, code)}
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
      condition inherit,
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3": 10.04}

      actions triggered_by: interval, at: "* * * * * *" do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Keyword.put(constants, :code, code)}
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
      constants: constants = [{:address, contract_address} | _]
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
      constants: constants = [{:address, contract_address} | _],
      expected_tx: expected_tx
    } do
      code = """
      condition inherit,
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3": 10.04}

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Keyword.put(constants, :code, code)}
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
           constants: constants = [{:address, contract_address} | _],
           expected_tx: expected_tx
         } do
      code = """
      condition transaction: regex_match?(content, \"^Mr.Y|Mr.X{1}$\")

      condition inherit,
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3": 10.04}

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Keyword.put(constants, :code, code)}
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
      constants: constants = [{:address, contract_address} | _],
      expected_tx: expected_tx
    } do
      code = ~s"""
      condition transaction: regex_match?(content, "^Mr.Y|Mr.X{1}$")

      condition inherit,
        uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3": 10.04}

      actions triggered_by: transaction do
        set_type transfer
        add_uco_transfer to: "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3", amount: 10.04
        set_code "
          condition transaction: regex_match?(content, \\"^Mr.Y|Mr.X{1}$\\")

          condition inherit,
            uco_transfers: %{ \\"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\\": 9.20}

          actions triggered_by: transaction do
            set_type transfer
            add_uco_transfer to: \\"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\\", amount: 9.20
          end"
      end
      """

      {:ok, contract} = Interpreter.parse(code)

      contract = %{
        contract
        | constants: %Constants{contract: Keyword.put(constants, :code, code)}
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
    condition transaction: regex_match?(content, \"^Mr.Y|Mr.X{1}$\")

    condition inherit,
      uco_transfers: %{ \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\": 9.20}

    actions triggered_by: transaction do
      set_type transfer
      add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 9.20
    end"
      after
        3_000 ->
          raise "Timeout"
      end
    end
  end
end
