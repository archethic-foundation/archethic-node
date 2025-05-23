defmodule ArchethicWeb.API.REST.TransactionControllerTest do
  use ArchethicCase
  import ArchethicCase
  use ArchethicWeb.ConnCase

  alias Archethic.OracleChain
  alias Archethic.OracleChain.MemTable
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress

  alias Archethic.ContractFactory

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

    :ok
  end

  describe "transaction_fee/2" do
    test "should send ok response and return fee for valid transaction body", %{conn: conn} do
      previous_oracle_time =
        DateTime.utc_now()
        |> OracleChain.get_last_scheduling_date()
        |> OracleChain.get_last_scheduling_date()

      MemTable.add_oracle_data("uco", %{"eur" => 0.2, "usd" => 0.2}, previous_oracle_time)

      conn =
        post(conn, "/api/transaction_fee", %{
          "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
          "data" => %{
            "ledger" => %{
              "token" => %{"transfers" => []},
              "uco" => %{
                "transfers" => [
                  %{
                    "amount" => 100_000_000,
                    "to" => "000098fe10e8633bce19c59a40a089731c1f72b097c5a8f7dc71a37eb26913aa4f80"
                  }
                ]
              }
            }
          },
          "originSignature" =>
            "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
          "previousPublicKey" =>
            "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
          "previousSignature" =>
            "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
          "type" => "transfer",
          "version" => current_transaction_version()
        })

      assert %{
               "fee" => 0,
               "rates" => %{
                 "eur" => 0.2,
                 "usd" => 0.2
               }
             } = json_response(conn, 200)
    end

    test "should send bad_request response for invalid transaction body", %{conn: conn} do
      conn = post(conn, "/api/transaction_fee", %{})

      assert %{
               "errors" => %{
                 "address" => [
                   "can't be blank"
                 ],
                 "data" => [
                   "can't be blank"
                 ],
                 "originSignature" => [
                   "can't be blank"
                 ],
                 "previousPublicKey" => [
                   "can't be blank"
                 ],
                 "previousSignature" => [
                   "can't be blank"
                 ],
                 "type" => [
                   "can't be blank"
                 ],
                 "version" => [
                   "can't be blank"
                 ]
               },
               "status" => "invalid"
             } = json_response(conn, 400)
    end
  end

  describe "simulate_contract_execution/2" do
    test "should validate the latest contract from the chain", %{conn: conn} do
      contract_tx =
        %Transaction{address: last_contract_address} =
        """
        condition inherit: [
          type: transfer,
          content: true,
          uco_transfers: true
        ]

        condition transaction: [
          content: "test content"
        ]

        actions triggered_by: transaction do
          set_type transfer
          add_uco_transfer to: "000030831178cd6a49fe446778455a7a980729a293bfa16b0a1d2743935db210da76", amount: 1337
        end
        """
        |> ContractFactory.create_valid_contract_tx(content: "hello")

      # test
      old_contract_address = <<0::16, :crypto.strong_rand_bytes(32)::binary>>
      old_contract_address_hex = Base.encode16(old_contract_address)

      MockClient
      |> stub(:send_message, fn
        _, %GetTransaction{address: ^last_contract_address}, _ ->
          {:ok, contract_tx}

        _, %GetLastTransactionAddress{address: ^old_contract_address}, _ ->
          {:ok, %LastTransactionAddress{address: last_contract_address}}
      end)

      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          "content" => "7465737420636f6e74656e74",
          "recipients" => [%{"address" => old_contract_address_hex}]
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => 3
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)

      assert(
        match?(
          [%{"valid" => true, "recipient_address" => ^old_contract_address_hex}],
          json_response(conn, 200)
        )
      )
    end

    test "should indicate faillure when asked to validate an invalid contract", %{conn: conn} do
      previous_tx =
        %Transaction{address: contract_address} =
        """
        condition inherit: [
          type: transfer,
          content: false,
          uco_transfers: true
        ]

        condition transaction: [
          uco_transfers: size() > 0
        ]

        actions triggered_by: transaction do
          set_type transfer
          add_uco_transfer to: "000030831178cd6a49fe446778455a7a980729a293bfa16b0a1d2743935db210da76", amount: 1337
        end
        """
        |> ContractFactory.create_valid_contract_tx(content: "hello")

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: _}, _ ->
        {:ok, previous_tx}
      end)

      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          "content" => "0000",
          "recipients" => [
            %{"address" => Base.encode16(contract_address)}
          ]
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => current_transaction_version()
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)

      assert(match?([%{"valid" => false}], json_response(conn, 200)))
    end

    test "should indicate when body fails changeset validation", %{conn: conn} do
      previous_tx =
        %Transaction{address: contract_address} =
        """
        condition inherit: [
          type: transfer,
          content: false,
          uco_transfers: true
        ]

        condition transaction: [
          uco_transfers: size() > 0
        ]

        actions triggered_by: transaction do
          set_type transfer
          add_uco_transfer to: "000030831178cd6a49fe446778455a7a980729a293bfa16b0a1d2743935db210da76", amount: 1337
        end
        """
        |> ContractFactory.create_valid_contract_tx(content: "hello")

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: _}, _ ->
        {:ok, previous_tx}
      end)

      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          ## Next line is the invalid part
          "content" => "hola",
          "recipients" => [
            %{"address" => Base.encode16(contract_address)}
          ]
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => 3
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)

      assert(match?([%{"valid" => false}], json_response(conn, 200)))
    end

    test "should indicate faillure when failling parsing of contracts", %{conn: conn} do
      ## SC is missing the "inherit" keyword
      previous_tx =
        %Transaction{address: contract_address} =
        """
        condition : [
          type: transfer,
          content: true,
          uco_transfers: true
        ]

        condition transaction: [
          uco_transfers: size() > 0
        ]

        actions triggered_by: transaction do
          set_type transfer
          add_uco_transfer to: "000030831178cd6a49fe446778455a7a980729a293bfa16b0a1d2743935db210da76", amount: 1337
        end
        """
        |> ContractFactory.create_valid_contract_tx()

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: _}, _ ->
        {:ok, previous_tx}
      end)

      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          "recipients" => [
            %{"address" => Base.encode16(contract_address)}
          ]
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => current_transaction_version()
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)

      assert(match?([%{"valid" => false}], json_response(conn, 200)))
    end

    test "Assert empty contract are not simulated and return negative answer", %{conn: conn} do
      previous_tx =
        %Transaction{address: contract_address} = ContractFactory.create_valid_contract_tx("")

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: _}, _ ->
        {:ok, previous_tx}
      end)

      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          "recipients" => [
            %{"address" => Base.encode16(contract_address)}
          ]
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => 3
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)
      assert(match?([%{"valid" => false}], json_response(conn, 200)))
    end

    test "should return error answer when asked to validate a crashing contract", %{conn: conn} do
      code = """
      condition inherit: [
        content: true
      ]

      condition transaction: [
        uco_transfers: size() > 0
      ]

      actions triggered_by: transaction do
        set_content 10 / 0
      end
      """

      previous_tx1 =
        %Transaction{address: contract_address1} =
        ContractFactory.create_valid_contract_tx(code, content: "hello", seed: "seed1")

      previous_tx2 =
        %Transaction{address: contract_address2} =
        ContractFactory.create_valid_contract_tx(code, content: "hello", seed: "seed2")

      MockClient
      |> expect(:send_message, 2, fn
        _, %GetTransaction{address: ^contract_address1}, _ -> {:ok, previous_tx1}
        _, %GetTransaction{address: ^contract_address2}, _ -> {:ok, previous_tx2}
      end)

      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          "code" => code,
          "content" => "0000",
          "recipients" => [
            %{"address" => Base.encode16(contract_address1)},
            %{"address" => Base.encode16(contract_address2)}
          ]
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => 3
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)

      assert(match?([%{"valid" => false}, %{"valid" => false}], json_response(conn, 200)))
    end

    test "should return an error if there is no recipients", %{conn: conn} do
      new_tx = %{
        "address" => "00009e059e8171643b959284fe542909f3b32198b8fc25b3e50447589b84341c1d67",
        "data" => %{
          "code" => "",
          "content" => "0000",
          "recipients" => []
        },
        "originSignature" =>
          "3045022024f8d254671af93f8b9c11b5a2781a4a7535d2e89bad69d6b1f142f8f4bcf489022100c364e10f5f846b2534a7ace4aeaa1b6c8cb674f842b9f8bc78225dfa61cabec6",
        "previousPublicKey" =>
          "000071e1b5d4b89eddf2322c69bbf1c5591f7361b24cb3c4c464f6b5eb688fe50f7a",
        "previousSignature" =>
          "9b209dd92c6caffbb5c39d12263f05baebc9fe3c36cb0f4dde04c96f1237b75a3a2973405c6d9d5e65d8a970a37bafea57b919febad46b0cceb04a7ffa4b6b00",
        "type" => "transfer",
        "version" => current_transaction_version()
      }

      conn = post(conn, "/api/transaction/contract/simulator", new_tx)

      assert(
        match?(
          [%{"valid" => false, "reason" => "There are no recipients in the transaction"}],
          json_response(conn, 200)
        )
      )
    end
  end
end
