defmodule Archethic.Mining.SmartContractValidationTest do
  use ArchethicCase

  alias Archethic.Mining.SmartContractValidation
  alias Archethic.P2P
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient

  import Mox

  describe "valid_contract_calls?/2" do
    test "returns true if all contracts calls are valid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true}}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true}}
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

      assert SmartContractValidation.valid_contract_calls?(
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

    test "returns false if any contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: false}}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true}}
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

      refute SmartContractValidation.valid_contract_calls?(
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

    test "returns false if one node replying asserting the contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          %Node{port: 1234},
          %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}},
          _ ->
            {:ok, %SmartContractCallValidation{valid?: false}}

          %Node{port: 1235},
          %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}},
          _ ->
            {:ok, %SmartContractCallValidation{valid?: true}}
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

      refute SmartContractValidation.valid_contract_calls?(
               [%Recipient{address: "@SC1"}],
               %Transaction{},
               DateTime.utc_now()
             )
    end

    test "returns false if one smart contract is invalid" do
      MockClient
      |> stub(
        :send_message,
        fn
          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC1"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: false}}

          _, %ValidateSmartContractCall{recipient: %Recipient{address: "@SC2"}}, _ ->
            {:ok, %SmartContractCallValidation{valid?: true}}
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

      refute SmartContractValidation.valid_contract_calls?(
               [%Recipient{address: "@SC1"}, %Recipient{address: "@SC2"}],
               %Transaction{},
               DateTime.utc_now()
             )
    end
  end
end
