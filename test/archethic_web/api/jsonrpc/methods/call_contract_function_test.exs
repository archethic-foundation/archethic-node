defmodule ArchethicWeb.API.JsonRPC.Methods.CallContractFunctionTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Method.CallContractFunction

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.SelfRepair.NetworkView

  import Mox

  setup do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.last_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    start_supervised!(NetworkView)

    :ok
  end

  describe "validate_params" do
    test "should send bad_request response for invalid transaction body" do
      assert {:error,
              %{
                contract: [
                  "can't be blank"
                ],
                function: [
                  "can't be blank"
                ]
              }} = CallContractFunction.validate_params(%{})
    end
  end

  describe "execute" do
    test "should indicate faillure when failling parsing of contracts" do
      code = """
      condition transaction: [
        content: "test"
      ]

      actions triggered_by: transaction do
        Contract.not_exists
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: _}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "get_content",
        args: []
      }

      assert {:error, :parsing_contract, _, _} = CallContractFunction.execute(params)
    end

    test "should be able to call public function without parameters" do
      code = """
      @version 1

      export fun get_content() do 
        contract.content
      end

      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content get_content()
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code,
          content: "I'm a content !"
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "get_content",
        args: []
      }

      assert {:ok, "I'm a content !"} == CallContractFunction.execute(params)
    end

    test "should be able to call public function with parameters" do
      code = """
      @version 1

      export fun sum(list_of_number) do 
        sum = 0
        for number in list_of_number do
          sum = sum + number
        end
        sum
      end

      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content "toto"
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "sum",
        args: [
          [1, 2, 3, 4, 5, 6]
        ]
      }

      assert {:ok, 21.0} == CallContractFunction.execute(params)
    end

    test "should be able to call a public function from a public function" do
      code = """
      @version 1

      export fun bob() do 
        "hello bob"
      end
      export fun hello() do 
        bob()
      end

      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content hello()
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: []
      }

      assert {:ok, "hello bob"} == CallContractFunction.execute(params)
    end

    test "should not be able to call a private function from a public function" do
      code = """
      @version 1

      fun bob() do 
        "hello bob"
      end
      export fun hello() do 
        bob()
      end

      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content hello()
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: []
      }

      assert {:error, :function_failure, "There was an error while executing the function",
              "hello/0"} = CallContractFunction.execute(params)
    end

    test "should return error when called function does not exist" do
      code = """
      @version 1

      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content "hello"
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: []
      }

      assert {:error, :function_does_not_exist,
              "The function you are trying to call does not exist",
              "hello/0"} = CallContractFunction.execute(params)
    end

    test "should return error when function is called with bad arity" do
      code = """
      @version 1

      export fun hello(a, b) do 
        a + b
      end
      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content "hello"
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [1]
      }

      assert {:error, :function_does_not_exist,
              "The function you are trying to call does not exist",
              "hello/1"} = CallContractFunction.execute(params)
    end

    test "should return error when function call failed" do
      code = """
      @version 1

      export fun hello(a, b) do 
        a + b
      end
      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content "hello"
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [1, "not a number"]
      }

      assert {:error, :function_failure, "There was an error while executing the function",
              "hello/2"} = CallContractFunction.execute(params)
    end

    test "should return error when calling private function" do
      code = """
      @version 1

      fun hello(a, b) do 
        a + b
      end
      condition transaction: [
      ]

      actions triggered_by: transaction do
          Contract.set_content "hello"
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :transfer,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_address}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [1, 2]
      }

      assert {:error, :function_is_private, "The function you are trying to call is private",
              "hello/2"} = CallContractFunction.execute(params)
    end
  end
end
