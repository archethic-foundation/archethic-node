defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.Contract.Conditions
  alias Archethic.Contracts.Contract.Constants
  alias Archethic.Contracts.Contract.Trigger

  alias Archethic.Contracts.Interpreter

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.FirstAddress
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  import Mox

  doctest Interpreter

  describe "parse/1" do
    test "should parse a contract with some standard functions" do
      assert {:ok,
              %Contract{
                triggers: [
                  %Trigger{
                    type: :transaction,
                    actions: {
                      :__block__,
                      [],
                      [
                        {
                          :=,
                          [line: 2],
                          [
                            {:scope, [line: 2], nil},
                            {
                              :update_in,
                              [line: 2],
                              [
                                {:scope, [line: 2], nil},
                                ["next_transaction"],
                                {:&, [line: 2],
                                 [
                                   {{:., [line: 2],
                                     [
                                       {:__aliases__,
                                        [
                                          alias:
                                            Archethic.Contracts.Interpreter.TransactionStatements
                                        ], [:TransactionStatements]},
                                       :set_type
                                     ]}, [line: 2], [{:&, [line: 2], [1]}, "transfer"]}
                                 ]}
                              ]
                            }
                          ]
                        },
                        {
                          :=,
                          [line: 3],
                          [
                            {:scope, [line: 3], nil},
                            {
                              :update_in,
                              [line: 3],
                              [
                                {:scope, [line: 3], nil},
                                ["next_transaction"],
                                {
                                  :&,
                                  [line: 3],
                                  [
                                    {
                                      {:., [line: 3],
                                       [
                                         {:__aliases__,
                                          [
                                            alias:
                                              Archethic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_uco_transfer
                                       ]},
                                      [line: 3],
                                      [
                                        {:&, [line: 3], [1]},
                                        [
                                          {"to",
                                           <<127, 102, 97, 172, 226, 130, 249, 71, 172, 162, 239,
                                             148, 125, 1, 189, 220, 144, 198, 95, 9, 238, 130,
                                             139, 218, 222, 46, 62, 212, 37, 132, 112, 179>>},
                                          {"amount", 1_040_000_000}
                                        ]
                                      ]
                                    }
                                  ]
                                }
                              ]
                            }
                          ]
                        },
                        {
                          :=,
                          [line: 4],
                          [
                            {:scope, [line: 4], nil},
                            {
                              :update_in,
                              [line: 4],
                              [
                                {:scope, [line: 4], nil},
                                ["next_transaction"],
                                {
                                  :&,
                                  [line: 4],
                                  [
                                    {
                                      {:., [line: 4],
                                       [
                                         {:__aliases__,
                                          [
                                            alias:
                                              Archethic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_token_transfer
                                       ]},
                                      [line: 4],
                                      [
                                        {:&, [line: 4], [1]},
                                        [
                                          {"to",
                                           <<48, 103, 4, 85, 113, 62, 44, 190, 207, 148, 89, 18,
                                             38, 169, 3, 101, 30, 216, 98, 86, 53, 24, 29, 218,
                                             35, 111, 236, 194, 33, 209, 231, 228>>},
                                          {"amount", 20_000_000_000},
                                          {"token_address",
                                           <<174, 180, 166, 245, 171, 109, 130, 190, 34, 60, 88,
                                             103, 235, 165, 254, 97, 111, 82, 244, 16, 220, 248,
                                             59, 69, 175, 241, 88, 221, 64, 174, 138, 195>>},
                                          {"token_id", 0}
                                        ]
                                      ]
                                    }
                                  ]
                                }
                              ]
                            }
                          ]
                        },
                        {
                          :=,
                          [line: 5],
                          [
                            {:scope, [line: 5], nil},
                            {
                              :update_in,
                              [line: 5],
                              [
                                {:scope, [line: 5], nil},
                                ["next_transaction"],
                                {
                                  :&,
                                  [line: 5],
                                  [
                                    {{:., [line: 5],
                                      [
                                        {:__aliases__,
                                         [
                                           alias:
                                             Archethic.Contracts.Interpreter.TransactionStatements
                                         ], [:TransactionStatements]},
                                        :set_content
                                      ]}, [line: 5], [{:&, [line: 5], [1]}, "Receipt"]}
                                  ]
                                }
                              ]
                            }
                          ]
                        },
                        {
                          :=,
                          [line: 6],
                          [
                            {:scope, [line: 6], nil},
                            {
                              :update_in,
                              [line: 6],
                              [
                                {:scope, [line: 6], nil},
                                ["next_transaction"],
                                {
                                  :&,
                                  [line: 6],
                                  [
                                    {
                                      {:., [line: 6],
                                       [
                                         {:__aliases__,
                                          [
                                            alias:
                                              Archethic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_ownership
                                       ]},
                                      [line: 6],
                                      [
                                        {:&, [line: 6], [1]},
                                        [
                                          {"secret", "MyEncryptedSecret"},
                                          {"secret_key", "MySecretKey"},
                                          {"authorized_public_keys",
                                           [
                                             <<112, 194, 69, 229, 217, 112, 181, 157, 246, 86, 56,
                                               189, 213, 217, 99, 238, 34, 230, 216, 146, 234, 34,
                                               77, 136, 9, 208, 251, 117, 208, 177, 144, 122>>
                                           ]}
                                        ]
                                      ]
                                    }
                                  ]
                                }
                              ]
                            }
                          ]
                        },
                        {
                          :=,
                          [line: 7],
                          [
                            {:scope, [line: 7], nil},
                            {
                              :update_in,
                              [line: 7],
                              [
                                {:scope, [line: 7], nil},
                                ["next_transaction"],
                                {
                                  :&,
                                  [line: 7],
                                  [
                                    {
                                      {:., [line: 7],
                                       [
                                         {:__aliases__,
                                          [
                                            alias:
                                              Archethic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_recipient
                                       ]},
                                      [line: 7],
                                      [
                                        {:&, [line: 7], [1]},
                                        <<120, 39, 60, 92, 188, 235, 134, 23, 245, 67, 128, 204,
                                          47, 23, 61, 242, 64, 77, 182, 118, 201, 241, 13, 84,
                                          107, 111, 57, 94, 111, 59, 221, 238>>
                                      ]
                                    }
                                  ]
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  }
                ]
              }} =
               """
               actions triggered_by: transaction do
                 set_type transfer
                 add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1040000000
                 add_token_transfer to: \"30670455713E2CBECF94591226A903651ED8625635181DDA236FECC221D1E7E4\", amount: 20000000000, token_address: \"AEB4A6F5AB6D82BE223C5867EBA5FE616F52F410DCF83B45AFF158DD40AE8AC3\", token_id: 0
                 set_content \"Receipt\"
                 add_ownership secret: \"MyEncryptedSecret\", secret_key: \"MySecretKey\", authorized_public_keys: ["70C245E5D970B59DF65638BDD5D963EE22E6D892EA224D8809D0FB75D0B1907A"]
                 add_recipient \"78273C5CBCEB8617F54380CC2F173DF2404DB676C9F10D546B6F395E6F3BDDEE\"
               end
               """
               |> Interpreter.parse()
    end

    test "should parse a contract with some map based inherit constraints" do
      assert {:ok,
              %Contract{
                conditions: %{
                  inherit: %Conditions{
                    uco_transfers:
                      {:==, _,
                       [
                         {:get_in, _,
                          [
                            {:scope, _, nil},
                            ["next", "uco_transfers"]
                          ]},
                         [
                           {:%{}, _,
                            [
                              {"to",
                               <<127, 102, 97, 172, 226, 130, 249, 71, 172, 162, 239, 148, 125, 1,
                                 189, 220, 144, 198, 95, 9, 238, 130, 139, 218, 222, 46, 62, 212,
                                 37, 132, 112, 179>>},
                              {"amount", 1_040_000_000}
                            ]}
                         ]
                       ]}
                  }
                }
              }} =
               """
               condition inherit: [
                 uco_transfers: [%{ to: "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3", amount: 1040000000 }]
               ]

               actions triggered_by: datetime, at: 1102190390 do
                 set_type transfer
                 add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 1040000000
               end
               """
               |> Interpreter.parse()
    end

    test "should parse multiline inherit constraints" do
      assert {:ok,
              %Contract{
                conditions: %{
                  inherit: %Conditions{
                    uco_transfers:
                      {:==, _,
                       [
                         {:get_in, _, [{:scope, _, nil}, ["next", "uco_transfers"]]},
                         [
                           {:%{}, _,
                            [
                              {"to",
                               <<127, 102, 97, 172, 226, 130, 249, 71, 172, 162, 239, 148, 125, 1,
                                 189, 220, 144, 198, 95, 9, 238, 130, 139, 218, 222, 46, 62, 212,
                                 37, 132, 112, 179>>},
                              {"amount", 1_040_000_000}
                            ]}
                         ]
                       ]},
                    content:
                      {:==, _, [{:get_in, _, [{:scope, _, nil}, ["next", "content"]]}, "hello"]}
                  }
                }
              }} =
               """
                 condition inherit: [
                   uco_transfers: [%{ to: "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3", amount: 1040000000 }],
                   content: "hello"
                 ]

               """
               |> Interpreter.parse()
    end
  end

  describe "execute_actions/2" do
    test "should evaluate actions based on if statement" do
      {:ok, contract} =
        ~S"""
        actions triggered_by: transaction do
          if transaction.previous_public_key == "abc" do
            set_content "yes"
          else
            set_content "no"
          end
        end
        """
        |> Interpreter.parse()

      assert %Transaction{data: %TransactionData{content: "yes"}} =
               Interpreter.execute_actions(contract, :transaction, %{
                 "transaction" => %{"previous_public_key" => "abc"}
               })
    end

    test "should use a variable assignation" do
      {:ok, contract} =
        """
          actions triggered_by: transaction do
            new_content = \"hello\"
            set_content new_content
          end
        """
        |> Interpreter.parse()

      assert %Transaction{data: %TransactionData{content: "hello"}} =
               Interpreter.execute_actions(contract, :transaction)
    end

    test "should use a interpolation assignation" do
      {:ok, contract} =
        ~S"""
          actions triggered_by: transaction do
            new_content = "hello #{2+2}"
            set_content new_content
          end
        """
        |> Interpreter.parse()

      assert %Transaction{data: %TransactionData{content: "hello 4"}} =
               Interpreter.execute_actions(contract, :transaction)
    end

    test "should flatten comparison operators" do
      code = """
      condition inherit: [
        content: size() >= 10
      ]
      """

      {:ok,
       %Contract{
         conditions: %{
           inherit: %Conditions{
             content:
               {:>=, [line: 2],
                [
                  {{:., [line: 2],
                    [
                      {:__aliases__, [alias: Archethic.Contracts.Interpreter.Library],
                       [:Library]},
                      :size
                    ]}, [line: 2],
                   [
                     {:get_in, [line: 2], [{:scope, [line: 2], nil}, ["next", "content"]]}
                   ]},
                  10
                ]}
           }
         }
       }} = Interpreter.parse(code)
    end

    test "should accept conditional code within condition" do
      {:ok, %Contract{}} =
        ~S"""
        condition inherit: [
          content: if type == transfer do
           regex_match?("hello")
          else
           regex_match?("hi")
          end
        ]

        """
        |> Interpreter.parse()
    end

    test "should accept different type of transaction keyword references" do
      {:ok, %Contract{}} =
        ~S"""
         condition inherit: [
          content: if next.type == transfer do
            "hi"
          else
            if previous.type == transfer do
              "hi"
            else
              "hello"
            end
          end
         ]

        condition transaction: [
          content: "#{hash(contract.code)} - YES"
        ]
        """
        |> Interpreter.parse()
    end
  end

  describe "execute/2" do
    test "should execute complex condition with if statements" do
      code = ~S"""
      condition inherit: [
        type: in?([transfer, token]),
        content: if type == transfer do
         regex_match?("reason transfer: (.*)")
        else
         regex_match?("reason token creation: (.*)")
        end,
      ]

      condition transaction: [
        content: hash(contract.code)
      ]
      """

      {:ok,
       %Contract{conditions: %{inherit: inherit_conditions, transaction: transaction_conditions}}} =
        Interpreter.parse(code)

      assert true ==
               Interpreter.valid_conditions?(inherit_conditions, %{
                 "next" => %{"type" => "transfer", "content" => "reason transfer: pay back alice"}
               })

      assert false ==
               Interpreter.valid_conditions?(inherit_conditions, %{
                 "next" => %{"type" => "transfer", "content" => "dummy"}
               })

      assert true ==
               Interpreter.valid_conditions?(inherit_conditions, %{
                 "next" => %{
                   "type" => "token",
                   "content" => "reason token creation: new super token"
                 }
               })

      assert true ==
               Interpreter.valid_conditions?(transaction_conditions, %{
                 "transaction" => %{"content" => :crypto.hash(:sha256, code)},
                 "contract" => %{"code" => code}
               })
    end
  end

  test "ICO contract parsing" do
    {:ok, _} =
      """
      condition inherit: [
      type: transfer,
      uco_transfers: size() == 1
      # TODO: to provide more security, we should check the destination address is within the previous transaction inputs
      ]


      actions triggered_by: transaction do
        # Get the amount of uco send to this contract
        amount_send = transaction.uco_transfers[contract.address]

        if amount_send > 0 do
          # Convert UCO to the number of tokens to credit. Each UCO worth 10000 token
          token_to_credit = amount_send * 10000

          # Send the new transaction
          set_type transfer
          add_token_transfer to: transaction.address, token_address: contract.address, amount: token_to_credit, token_id: token_id
        end
      end
      """
      |> Interpreter.parse()
  end

  describe "get_genesis_address/1" do
    setup do
      key = <<0::16, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: key,
        last_public_key: key,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      {:ok, [key: key]}
    end

    test "shall get the first address of the chain in the conditions" do
      address = "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
      b_address = Base.decode16!(address)

      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, %FirstAddress{address: b_address}}
      end)

      {:ok, %Contract{conditions: %{transaction: conditions}}} =
        ~s"""
        condition transaction: [
          address: get_genesis_address() == "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"

        ]
        """
        |> Interpreter.parse()

      assert true =
               Interpreter.valid_conditions?(
                 conditions,
                 %{"transaction" => %{"address" => :crypto.strong_rand_bytes(32)}}
               )
    end

    test "shall get the first public of the chain in the conditions" do
      public_key = "0001DDE54A313E5DCD73E413748CBF6679F07717F8BDC66CBE8F981E1E475A98605C"
      b_public_key = Base.decode16!(public_key)

      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, %FirstPublicKey{public_key: b_public_key}}
      end)

      {:ok, %Contract{conditions: %{transaction: conditions}}} =
        ~s"""
        condition transaction: [
          previous_public_key: get_genesis_public_key() == "0001DDE54A313E5DCD73E413748CBF6679F07717F8BDC66CBE8F981E1E475A98605C"
        ]
        """
        |> Interpreter.parse()

      assert true =
               Interpreter.valid_conditions?(
                 conditions,
                 %{
                   "transaction" => %{
                     "previous_public_key" =>
                       <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
                   }
                 }
               )
    end

    test "shall parse get_genesis_address/1 in actions" do
      address = "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
      b_address = Base.decode16!(address)

      MockClient
      |> expect(:send_message, fn _, _, _ ->
        {:ok, %FirstAddress{address: b_address}}
      end)

      {:ok, contract} =
        ~s"""
        actions triggered_by: transaction do
          address = get_genesis_address "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4"
          if address == "64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4" do
            set_content "yes"
          else
            set_content "no"
          end
        end
        """
        |> Interpreter.parse()

      assert %Transaction{data: %TransactionData{content: "yes"}} =
               Interpreter.execute_actions(contract, :transaction)
    end
  end
end
