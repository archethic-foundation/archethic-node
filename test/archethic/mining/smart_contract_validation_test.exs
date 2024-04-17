defmodule Archethic.Mining.SmartContractValidationTest do
  use ArchethicCase
  import ArchethicCase

  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.State
  alias Archethic.Mining.Error
  alias Archethic.Mining.SmartContractValidation
  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TransactionFactory

  import Mox

  doctest SmartContractValidation

  describe "validate_contract_calls/2" do
    test "should returns fees if all contracts calls are valid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: :ok,
               fee: 123_456,
               last_chain_sync_date: DateTime.utc_now()
             }}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: :ok,
               fee: 654_321,
               last_chain_sync_date: DateTime.utc_now()
             }}
        end
      )

      node = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node)

      assert {:ok, 777_777} =
               SmartContractValidation.validate_contract_calls(
                 [
                   %Recipient{address: "@SC1"},
                   %Recipient{address: "@SC2", action: "do_something", args: [1, 2, 3]}
                 ],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end

    test "should returns error if any contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: {:error, :invalid_condition, "content"},
               fee: 0,
               last_chain_sync_date: DateTime.utc_now()
             }}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: :ok,
               fee: 0,
               last_chain_sync_date: DateTime.utc_now()
             }}
        end
      )

      node = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node)

      assert {:error, %Error{data: %{"message" => "Invalid condition on content"}}} =
               SmartContractValidation.validate_contract_calls(
                 [
                   %Recipient{address: "@SC1"},
                   %Recipient{
                     address: "@SC2",
                     action: "do_something",
                     args: [1, 2, 3]
                   }
                 ],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end

    test "should resolve the conflict (ok)" do
      last_chain_sync_date = DateTime.utc_now()

      node1 = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      node2 = %Node{
        ip: "127.0.0.1",
        port: 1235,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)

      MockClient
      |> stub(
        :send_message,
        fn
          ^node1, %ValidateSmartContractCall{}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: :ok,
               fee: 777_777,
               last_chain_sync_date: last_chain_sync_date
             }}

          ^node2, %ValidateSmartContractCall{}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: {:error, :transaction_not_exists},
               fee: 0,
               last_chain_sync_date: last_chain_sync_date
             }}
        end
      )

      assert {:ok, _} =
               SmartContractValidation.validate_contract_calls(
                 [%Recipient{address: random_address()}],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end

    test "should resolve the conflict (last_chain_sync_date)" do
      node1 = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      node2 = %Node{
        ip: "127.0.0.1",
        port: 1235,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)

      MockClient
      |> stub(
        :send_message,
        fn
          ^node1, %ValidateSmartContractCall{}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: :ok,
               fee: 777_777,
               last_chain_sync_date: ~U[2024-04-10 00:00:00Z]
             }}

          ^node2, %ValidateSmartContractCall{}, _ ->
            {:ok,
             %SmartContractCallValidation{
               status: {:error, :invalid_condition, "content"},
               fee: 0,
               last_chain_sync_date: ~U[2024-04-09 00:00:00Z]
             }}
        end
      )

      assert {:ok, _} =
               SmartContractValidation.validate_contract_calls(
                 [%Recipient{address: random_address()}],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end
  end

  describe "validate_contract_execution/5" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: random_public_key(),
        last_public_key: random_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      :ok
    end

    test "should return false if there is no context and there is a trigger" do
      now = ~U[2023-06-20 12:00:00Z]

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "wake up")

      genesis = Transaction.previous_address(prev_tx)

      assert {:error, %Error{data: "Contract has not been triggered"}} =
               SmartContractValidation.validate_contract_execution(
                 nil,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return true if there is no context and there is no trigger" do
      code = """
      @version 1
      condition inherit: [ content: true ]
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx,
          content: "{\"uco\":{\"eur\":0.00, \"usd\":0.00}}",
          type: :oracle
        )

      genesis = Transaction.previous_address(prev_tx)

      assert {:ok, nil} =
               SmartContractValidation.validate_contract_execution(
                 nil,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return true when the transaction have been triggered by datetime and timestamp matches" do
      now = %DateTime{DateTime.utc_now() | second: 0, microsecond: {0, 0}}

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "wake up")

      contract_context = %Contract.Context{
        trigger: {:datetime, now},
        status: :tx_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:ok, nil} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should work with contract version 0" do
      now = %DateTime{DateTime.utc_now() | second: 0, microsecond: {0, 0}}

      code = """
      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        set_content "wake up"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "wake up")

      contract_context = %Contract.Context{
        trigger: {:datetime, now},
        status: :tx_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:ok, nil} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return false when the transaction have been triggered by datetime but timestamp doesn't match" do
      yesterday = %DateTime{
        (DateTime.utc_now()
         |> DateTime.add(-1, :day))
        | second: 0,
          microsecond: {0, 0}
      }

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(yesterday)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "wake up")

      contract_context = %Contract.Context{
        trigger: {:datetime, yesterday},
        status: :tx_output,
        timestamp: DateTime.utc_now()
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:error, %Error{data: %{"message" => "Invalid trigger datetime"}}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return true when the transaction have been triggered by interval and timestamp matches" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "beep")

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:ok, nil} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return false when the transaction have been triggered by interval but timestamp doesn't match" do
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "beep")

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", yesterday},
        status: :tx_output,
        timestamp: DateTime.utc_now()
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:error, %Error{data: %{"message" => "Invalid trigger interval"}}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return true when the resulting transaction is the same as next_transaction" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "beep")

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:ok, nil} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return false when the resulting transaction is not the same as next_transaction" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        Contract.set_content "beep"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "boop")

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:error, %Error{data: "Transaction does not match expected result"}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return encoded_state if execution is valid" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        State.set("truth", 42)
        Contract.set_content "beep"
      end
      """

      encoded_state = State.serialize(%{"truth" => 42})

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx, content: "beep", state: encoded_state)

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :tx_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:ok, ^encoded_state} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return false if the context status is failure" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        State.set("truth", 42)
        Contract.set_content "beep"
      end
      """

      encoded_state = State.serialize(%{"truth" => 42})

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx, content: "beep", state: encoded_state)

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :failure,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:error, %Error{data: "Contract should not output a transaction"}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return false if the context status is no_output" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      code = """
      @version 1
      actions triggered_by: interval, at: "* * * * *" do
        State.set("truth", 42)
        Contract.set_content "beep"
      end
      """

      encoded_state = State.serialize(%{"truth" => 42})

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx =
        ContractFactory.create_next_contract_tx(prev_tx, content: "beep", state: encoded_state)

      contract_context = %Contract.Context{
        trigger: {:interval, "* * * * *", now},
        status: :no_output,
        timestamp: now
      }

      genesis = Transaction.previous_address(prev_tx)

      assert {:error, %Error{data: "Contract should not output a transaction"}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_tx,
                 genesis,
                 next_tx,
                 []
               )
    end

    test "should return true if transaction trigger is in inputs and recipient is the expected one" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("content")
        end
      """

      prev_contract_tx = ContractFactory.create_valid_contract_tx(code)
      contract_genesis = Transaction.previous_address(prev_contract_tx)

      recipient = %Recipient{action: "test", args: [], address: contract_genesis}

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([], recipients: [recipient])

      unspent_outputs = [%UnspentOutput{from: trigger_address, type: :call}]

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      next_contract_tx =
        ContractFactory.create_next_contract_tx(prev_contract_tx,
          inputs: [],
          content: "content"
        )

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{address: ^trigger_address}, _ ->
        {:ok, trigger_tx}
      end)

      contract_context = %Contract.Context{
        trigger: {:transaction, trigger_address, recipient},
        status: :tx_output,
        timestamp: trigger_tx.validation_stamp.timestamp,
        inputs: []
      }

      assert {:ok, nil} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_contract_tx,
                 contract_genesis,
                 next_contract_tx,
                 v_unspent_outputs
               )
    end

    test "should return false if transaction trigger is not in inputs" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("content")
        end
      """

      prev_contract_tx = ContractFactory.create_valid_contract_tx(code)
      contract_genesis = Transaction.previous_address(prev_contract_tx)

      recipient = %Recipient{action: "test", args: [], address: contract_genesis}

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([], recipients: [recipient])

      next_contract_tx =
        ContractFactory.create_next_contract_tx(prev_contract_tx, content: "content")

      MockClient
      |> expect(:send_message, 0, fn _, %GetTransaction{address: ^trigger_address}, _ ->
        {:ok, trigger_tx}
      end)

      contract_context = %Contract.Context{
        trigger: {:transaction, trigger_address, recipient},
        status: :tx_output,
        timestamp: trigger_tx.validation_stamp.timestamp
      }

      assert {:error, %Error{data: %{"message" => "Invalid trigger transaction"}}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_contract_tx,
                 contract_genesis,
                 next_contract_tx,
                 []
               )
    end

    test "should return false if transaction trigger is in inputs but recipient is not the expected one" do
      code = """
        @version 1
        condition triggered_by: transaction, on: test(), as: []
        actions triggered_by: transaction, on: test() do
          Contract.set_content("content")
        end
      """

      prev_contract_tx = ContractFactory.create_valid_contract_tx(code)
      contract_genesis = Transaction.previous_address(prev_contract_tx)

      recipient = %Recipient{action: "test", args: [], address: contract_genesis}

      trigger_tx =
        %Transaction{address: trigger_address} =
        TransactionFactory.create_valid_transaction([], recipients: [recipient])

      unspent_outputs = [%UnspentOutput{from: trigger_address, type: :call}]

      v_unspent_outputs =
        VersionedUnspentOutput.wrap_unspent_outputs(unspent_outputs, current_protocol_version())

      next_contract_tx =
        ContractFactory.create_next_contract_tx(prev_contract_tx,
          inputs: [],
          content: "content"
        )

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{address: ^trigger_address}, _ ->
        {:ok, trigger_tx}
      end)

      contract_context = %Contract.Context{
        trigger: {:transaction, trigger_address, %Recipient{recipient | action: "otter"}},
        status: :tx_output,
        timestamp: trigger_tx.validation_stamp.timestamp,
        inputs: v_unspent_outputs
      }

      assert {:error, %Error{data: %{"message" => "Invalid trigger transaction"}}} =
               SmartContractValidation.validate_contract_execution(
                 contract_context,
                 prev_contract_tx,
                 contract_genesis,
                 next_contract_tx,
                 v_unspent_outputs
               )
    end
  end
end
