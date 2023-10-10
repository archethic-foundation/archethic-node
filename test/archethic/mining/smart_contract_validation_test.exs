defmodule Archethic.Mining.SmartContractValidationTest do
  use ArchethicCase

  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract
  alias Archethic.Mining.SmartContractValidation
  alias Archethic.P2P
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient

  import Mox

  describe "validate_contract_calls/2" do
    test "should returns {true, fees} if all contracts calls are valid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true, fee: 123_456}}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true, fee: 654_321}}
        end
      )

      node = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node)

      assert {true, 777_777} =
               SmartContractValidation.validate_contract_calls(
                 [
                   %Recipient{address: "@SC1"},
                   %Recipient{address: "@SC2", action: "do_something", args: [1, 2, 3]}
                 ],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end

    test "should returns {false, 0} if any contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: false, fee: 0}}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true, fee: 0}}
        end
      )

      node = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node)

      assert {false, 0} =
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

    test "should returns {false, 0} if one node replying asserting the contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          %Node{port: 1234},
          %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}},
          _ ->
            {:ok, %SmartContractCallValidation{valid?: false, fee: 0}}

          %Node{port: 1235},
          %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}},
          _ ->
            {:ok, %SmartContractCallValidation{valid?: true, fee: 123_456}}
        end
      )

      node1 = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      node2 = %Node{
        ip: "127.0.0.1",
        port: 1235,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)

      assert {false, 0} =
               SmartContractValidation.validate_contract_calls(
                 [%Recipient{address: "@SC1"}],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end

    test "should returns {false, 0} if one smart contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: false, fee: 0}}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true, fee: 123_456}}
        end
      )

      node1 = %Node{
        ip: "127.0.0.1",
        port: 1234,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      node2 = %Node{
        ip: "127.0.0.1",
        port: 1235,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA"
      }

      P2P.add_and_connect_node(node1)
      P2P.add_and_connect_node(node2)

      assert {false, 0} =
               SmartContractValidation.validate_contract_calls(
                 [%Recipient{address: "@SC1"}, %Recipient{address: "@SC2"}],
                 %Transaction{},
                 DateTime.utc_now()
               )
    end
  end

  describe "valid_contract_execution?/3" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: ArchethicCase.random_public_key(),
        last_public_key: ArchethicCase.random_public_key(),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now() |> DateTime.add(-1)
      })

      :ok
    end

    test "should return true if there is no context" do
      now = ~U[2023-06-20 12:00:00Z]

      code = """
      @version 1
      actions triggered_by: datetime, at: #{DateTime.to_unix(now)} do
        Contract.set_content "wake up"
      end
      """

      prev_tx = ContractFactory.create_valid_contract_tx(code)

      next_tx = ContractFactory.create_next_contract_tx(prev_tx, content: "wake up")

      assert {true, nil} =
               SmartContractValidation.valid_contract_execution?(nil, prev_tx, next_tx)
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

      assert {true, %Contract.Result.Success{}} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
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

      assert {true, %Contract.Result.Success{}} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
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

      assert {false, nil} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
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

      assert {true, %Contract.Result.Success{}} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
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

      assert {false, nil} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
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

      assert {true, %Contract.Result.Success{}} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
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

      assert {false, %Contract.Result.Success{}} =
               SmartContractValidation.valid_contract_execution?(
                 contract_context,
                 prev_tx,
                 next_tx
               )
    end
  end
end
