defmodule ArchethicWeb.API.JsonRPC.Methods.CallContractFunctionTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Method.CallContractFunction

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GenesisAddress

  alias Archethic.TransactionChain.Transaction

  alias Archethic.SelfRepair.NetworkView

  alias Archethic.ContractFactory

  import ArchethicCase
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
                contract: ["can't be blank"],
                function: ["can't be blank"],
                args: ["is invalid"],
                resolve_last: ["is invalid"]
              }} =
               CallContractFunction.validate_params(%{
                 args: "not a list",
                 resolve_last: "not a boolean"
               })
    end

    test "should set default variable" do
      contract_address = random_address()
      contract_address_hex = Base.encode16(contract_address)

      assert {:ok,
              %{
                contract: ^contract_address,
                function: "test",
                args: [],
                resolve_last: true
              }} =
               CallContractFunction.validate_params(%{
                 contract: contract_address_hex,
                 function: "test"
               })
    end
  end

  describe "execute" do
    test "should resolve last contract chain address" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1
        export fun public() do
          "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: contract_address}}
      end)
      |> expect(:send_message, fn _, %GetTransaction{address: _}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "public",
        args: [],
        resolve_last: true
      }

      assert {:ok, "hello"} = CallContractFunction.execute(params)
    end

    test "should not resolve last contract chain address" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1
        export fun public() do
          "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, 0, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: contract_address}}
      end)
      |> expect(:send_message, fn _, %GetTransaction{address: _}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "public",
        args: [],
        resolve_last: false
      }

      assert {:ok, "hello"} = CallContractFunction.execute(params)
    end

    test "should indicate faillure when failling parsing of contracts" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1
        condition triggered_by: transaction, as: [
          content: "test"
        ]

        actions triggered_by: transaction do
          Contract.not_exists
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{address: _}, _ -> {:ok, contract_tx} end)

      params = %{
        contract: contract_address_hex,
        function: "get_content",
        args: [],
        resolve_last: false
      }

      assert {:error, :parsing_contract, _, _} = CallContractFunction.execute(params)
    end

    test "should be able to call public function without parameters" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        export fun get_content() do
          contract.content
        end

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
            Contract.set_content get_content()
        end
        """
        |> ContractFactory.create_valid_contract_tx(content: "I'm a content !")

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "get_content",
        args: [],
        resolve_last: false
      }

      assert {:ok, "I'm a content !"} == CallContractFunction.execute(params)
    end

    test "should be able to call public function with parameters" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        export fun sum(list_of_number) do
          sum = 0
          for number in list_of_number do
            sum = sum + number
          end
          sum
        end

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
            Contract.set_content "toto"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "sum",
        args: [
          [1, 2, 3, 4, 5, 6]
        ],
        resolve_last: false
      }

      assert {:ok, 21.0} == CallContractFunction.execute(params)
    end

    test "should not be able to call a public function from a public function" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        export fun bob() do
          "hello bob"
        end

        export fun hello() do
          bob()
        end

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
            Contract.set_content hello()
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [],
        resolve_last: false
      }

      assert {:error, :parsing_contract, _,
              "not allowed to call function from public function - bob - L8"} =
               CallContractFunction.execute(params)
    end

    test "should not be able to call a private function from a public function" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        fun bob() do
          "hello bob"
        end
        export fun hello() do
          bob()
        end

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
            Contract.set_content hello()
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [],
        resolve_last: false
      }

      assert {:error, :parsing_contract, _,
              "not allowed to call function from public function - bob - L7"} =
               CallContractFunction.execute(params)
    end

    test "should return error when called function does not exist" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
            Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [],
        resolve_last: false
      }

      assert {:error, :function_does_not_exist, "There was an error while executing the function",
              "The function you are trying to call does not exist"} =
               CallContractFunction.execute(params)
    end

    test "should return error when function is called with bad arity" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        export fun hello(a, b) do
          a + b
        end
        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
            Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [1],
        resolve_last: false
      }

      assert {:error, :function_does_not_exist, "There was an error while executing the function",
              "The function you are trying to call does not exist"} =
               CallContractFunction.execute(params)
    end

    test "should return error when function call failed" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        export fun hello(a, b) do
          a + b
        end

        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
            Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [1, "not a number"],
        resolve_last: false
      }

      assert {:error, :function_failure, "There was an error while executing the function",
              "bad argument in arithmetic expression - L4"} = CallContractFunction.execute(params)
    end

    test "should return error when calling private function" do
      contract_tx =
        %Transaction{address: contract_address} =
        """
        @version 1

        fun hello(a, b) do
          a + b
        end

        condition triggered_by: transaction, as: []
        actions triggered_by: transaction do
            Contract.set_content "hello"
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      contract_address_hex = Base.encode16(contract_address)

      MockClient
      |> expect(:send_message, fn _, %GetTransaction{}, _ -> {:ok, contract_tx} end)
      |> expect(:send_message, fn _, %GetGenesisAddress{address: address}, _ ->
        {:ok, %GenesisAddress{address: address, timestamp: DateTime.utc_now()}}
      end)

      params = %{
        contract: contract_address_hex,
        function: "hello",
        args: [1, 2],
        resolve_last: false
      }

      assert {:error, :function_is_private, "There was an error while executing the function",
              "The function you are trying to call is private"} =
               CallContractFunction.execute(params)
    end
  end
end
