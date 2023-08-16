defmodule ArchethicWeb.API.JsonRPC.Methods.SimulateContractExecutionTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Method.SimulateContractExecution

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TransactionFactory

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
    test "should send error when transaction key is missing" do
      assert {:error,
              %{
                transaction: [
                  "is required"
                ]
              }} = SimulateContractExecution.validate_params(%{})
    end

    test "should send bad_request response for invalid transaction body" do
      assert {:error,
              %{
                address: [
                  "can't be blank"
                ],
                data: [
                  "can't be blank"
                ],
                originSignature: [
                  "can't be blank"
                ],
                previousPublicKey: [
                  "can't be blank"
                ],
                previousSignature: [
                  "can't be blank"
                ],
                type: [
                  "can't be blank"
                ],
                version: [
                  "can't be blank"
                ]
              }} = SimulateContractExecution.validate_params(%{"transaction" => %{}})
    end
  end

  describe "execute" do
    test "should validate the latest contract from the chain" do
      code = """
      @version 1

      condition transaction: [
        content: "test content"
      ]

      actions triggered_by: transaction do
        Contract.add_uco_transfer to: "000030831178cd6a49fe446778455a7a980729a293bfa16b0a1d2743935db210da76", amount: 1337
      end
      """

      old_contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      old_contract_address_hex = Base.encode16(old_contract_address)
      last_contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      contract_tx = %Transaction{
        address: last_contract_address,
        type: :contract,
        data: %TransactionData{
          code: code
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: ^last_contract_address}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{address: ^old_contract_address}, _ ->
          {:ok, %LastTransactionAddress{address: last_contract_address}}
      end)

      trigger_tx =
        TransactionFactory.create_non_valided_transaction(
          recipients: [
            %Recipient{address: old_contract_address}
          ],
          content: "test content"
        )

      assert {:ok, [%{"valid" => true, "recipient_address" => ^old_contract_address_hex}]} =
               SimulateContractExecution.execute(trigger_tx)
    end

    test "should indicate faillure when asked to validate an invalid contract" do
      code = """
      @version 1
      condition inherit: [
        content: false
      ]

      condition transaction: [
        content: "test"
      ]

      actions triggered_by: transaction do
        Contract.set_content("should not pass")
      end
      """

      contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex = Base.encode16(contract_address)

      contract_tx = %Transaction{
        address: contract_address,
        type: :contract,
        data: %TransactionData{
          code: code,
          content: "hello"
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

      trigger_tx =
        TransactionFactory.create_non_valided_transaction(
          content: "test",
          recipients: [%Recipient{address: contract_address}]
        )

      assert {:ok,
              [
                %{
                  "valid" => false,
                  "recipient_address" => ^contract_address_hex,
                  "error" => %{"code" => 207}
                }
              ]} = SimulateContractExecution.execute(trigger_tx)
    end

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

      trigger_tx =
        TransactionFactory.create_non_valided_transaction(
          content: "test",
          recipients: [%Recipient{address: contract_address}]
        )

      assert {:ok,
              [
                %{
                  "valid" => false,
                  "recipient_address" => ^contract_address_hex,
                  "error" => %{"code" => 208}
                }
              ]} = SimulateContractExecution.execute(trigger_tx)
    end

    test "Assert empty contract are not simulated and return negative answer" do
      code = ""

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

      trigger_tx =
        TransactionFactory.create_non_valided_transaction(
          content: "test",
          recipients: [%Recipient{address: contract_address}]
        )

      assert {:ok,
              [
                %{
                  "valid" => false,
                  "recipient_address" => ^contract_address_hex,
                  "error" => %{"code" => 208}
                }
              ]} = SimulateContractExecution.execute(trigger_tx)
    end

    test "should return error answer when asked to validate a crashing contract" do
      code = """
      @version 1

      condition transaction: [
        content: "test"
      ]

      actions triggered_by: transaction do
        Contract.set_content 10 / 0
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

      trigger_tx =
        TransactionFactory.create_non_valided_transaction(
          content: "test",
          recipients: [%Recipient{address: contract_address}]
        )

      assert {:ok,
              [
                %{
                  "valid" => false,
                  "recipient_address" => ^contract_address_hex,
                  "error" => %{"code" => 203}
                }
              ]} = SimulateContractExecution.execute(trigger_tx)
    end

    test "should return multiple response if there is multiple recipients" do
      code1 = """
      @version 1

      condition transaction: [
        content: "test"
      ]

      actions triggered_by: transaction do
        Contract.set_content 10 / 0
      end
      """

      code2 = """
      @version 1

      condition transaction: [
        content: "test"
      ]

      actions triggered_by: transaction do
        Contract.set_content "ok"
      end
      """

      contract_address1 = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex1 = Base.encode16(contract_address1)

      contract_tx1 = %Transaction{
        address: contract_address1,
        type: :transfer,
        data: %TransactionData{
          code: code1
        },
        version: 1
      }

      contract_address2 = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      contract_address_hex2 = Base.encode16(contract_address2)

      contract_tx2 = %Transaction{
        address: contract_address2,
        type: :transfer,
        data: %TransactionData{
          code: code2
        },
        version: 1
      }

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: ^contract_address1}, _ ->
          {:ok, contract_tx1}

        _, %GetTransaction{address: ^contract_address2}, _ ->
          {:ok, contract_tx2}

        _, %GetLastTransactionAddress{address: address}, _ ->
          {:ok, %LastTransactionAddress{address: address}}
      end)

      trigger_tx =
        TransactionFactory.create_non_valided_transaction(
          content: "test",
          recipients: [
            %Recipient{address: contract_address1},
            %Recipient{address: contract_address2}
          ]
        )

      assert {:ok,
              [
                %{
                  "valid" => false,
                  "recipient_address" => ^contract_address_hex1,
                  "error" => %{"code" => 203}
                },
                %{"valid" => true, "recipient_address" => ^contract_address_hex2}
              ]} = SimulateContractExecution.execute(trigger_tx)
    end

    test "should return an error if there is no recipients" do
      trigger_tx = TransactionFactory.create_non_valided_transaction()

      assert {:error, :no_recipients, _} = SimulateContractExecution.execute(trigger_tx)
    end
  end
end
