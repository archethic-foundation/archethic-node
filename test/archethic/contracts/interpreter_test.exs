defmodule ArchEthic.Contracts.InterpreterTest do
  use ExUnit.Case

  alias ArchEthic.Contracts.Contract
  alias ArchEthic.Contracts.Contract.Conditions
  alias ArchEthic.Contracts.Contract.Constants
  alias ArchEthic.Contracts.Contract.Trigger

  alias ArchEthic.Contracts.Interpreter

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger

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
                                ["contract"],
                                {:&, [line: 2],
                                 [
                                   {{:., [line: 2],
                                     [
                                       {:__aliases__,
                                        [
                                          alias:
                                            ArchEthic.Contracts.Interpreter.TransactionStatements
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
                                ["contract"],
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
                                              ArchEthic.Contracts.Interpreter.TransactionStatements
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
                                          {"amount", 10.04}
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
                                ["contract"],
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
                                              ArchEthic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_nft_transfer
                                       ]},
                                      [line: 4],
                                      [
                                        {:&, [line: 4], [1]},
                                        [
                                          {"to",
                                           <<48, 103, 4, 85, 113, 62, 44, 190, 207, 148, 89, 18,
                                             38, 169, 3, 101, 30, 216, 98, 86, 53, 24, 29, 218,
                                             35, 111, 236, 194, 33, 209, 231, 228>>},
                                          {"amount", 200.0},
                                          {"nft",
                                           <<174, 180, 166, 245, 171, 109, 130, 190, 34, 60, 88,
                                             103, 235, 165, 254, 97, 111, 82, 244, 16, 220, 248,
                                             59, 69, 175, 241, 88, 221, 64, 174, 138, 195>>}
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
                                ["contract"],
                                {
                                  :&,
                                  [line: 5],
                                  [
                                    {{:., [line: 5],
                                      [
                                        {:__aliases__,
                                         [
                                           alias:
                                             ArchEthic.Contracts.Interpreter.TransactionStatements
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
                                ["contract"],
                                {
                                  :&,
                                  [line: 6],
                                  [
                                    {{:., [line: 6],
                                      [
                                        {:__aliases__,
                                         [
                                           alias:
                                             ArchEthic.Contracts.Interpreter.TransactionStatements
                                         ], [:TransactionStatements]},
                                        :set_secret
                                      ]}, [line: 6], [{:&, [line: 6], [1]}, "MyEncryptedSecret"]}
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
                                ["contract"],
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
                                              ArchEthic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_authorized_key
                                       ]},
                                      [line: 7],
                                      [
                                        {:&, [line: 7], [1]},
                                        [
                                          {"public_key",
                                           <<112, 194, 69, 229, 217, 112, 181, 157, 246, 86, 56,
                                             189, 213, 217, 99, 238, 34, 230, 216, 146, 234, 34,
                                             77, 136, 9, 208, 251, 117, 208, 177, 144, 122>>},
                                          {"encrypted_secret_key",
                                           <<71, 68, 42, 253, 51, 143, 131, 189, 220, 222, 156,
                                             242, 174, 221, 105, 176, 33, 62, 127, 149, 110, 32,
                                             39, 105, 226, 144, 240, 226, 105, 94, 147, 81>>}
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
                          [line: 8],
                          [
                            {:scope, [line: 8], nil},
                            {
                              :update_in,
                              [line: 8],
                              [
                                {:scope, [line: 8], nil},
                                ["contract"],
                                {
                                  :&,
                                  [line: 8],
                                  [
                                    {
                                      {:., [line: 8],
                                       [
                                         {:__aliases__,
                                          [
                                            alias:
                                              ArchEthic.Contracts.Interpreter.TransactionStatements
                                          ], [:TransactionStatements]},
                                         :add_recipient
                                       ]},
                                      [line: 8],
                                      [
                                        {:&, [line: 8], [1]},
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
                 add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
                 add_nft_transfer to: \"30670455713E2CBECF94591226A903651ED8625635181DDA236FECC221D1E7E4\", amount: 200.0, nft: \"AEB4A6F5AB6D82BE223C5867EBA5FE616F52F410DCF83B45AFF158DD40AE8AC3\"
                 set_content \"Receipt\"
                 set_secret \"MyEncryptedSecret\"
                 add_authorized_key public_key: "70C245E5D970B59DF65638BDD5D963EE22E6D892EA224D8809D0FB75D0B1907A", encrypted_secret_key: \"47442AFD338F83BDDCDE9CF2AEDD69B0213E7F956E202769E290F0E2695E9351\"
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
                         {:get_in, _, [{:scope, _, nil}, ["next", "uco_transfers"]]},
                         {:%{}, _,
                          [
                            {<<127, 102, 97, 172, 226, 130, 249, 71, 172, 162, 239, 148, 125, 1,
                               189, 220, 144, 198, 95, 9, 238, 130, 139, 218, 222, 46, 62, 212,
                               37, 132, 112, 179>>, 10.04}
                          ]}
                       ]}
                  }
                }
              }} =
               """
               condition inherit: [
                 uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04 }
               ]

               actions triggered_by: datetime, at: 1102190390 do
                 set_type transfer
                 add_uco_transfer to: \"7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3\", amount: 10.04
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
                         {:%{}, _,
                          [
                            {<<127, 102, 97, 172, 226, 130, 249, 71, 172, 162, 239, 148, 125, 1,
                               189, 220, 144, 198, 95, 9, 238, 130, 139, 218, 222, 46, 62, 212,
                               37, 132, 112, 179>>, 10.04}
                          ]}
                       ]},
                    content:
                      {:==, _, [{:get_in, _, [{:scope, _, nil}, ["next", "content"]]}, "hello"]}
                  }
                }
              }} =
               """
                 condition inherit: [
                   uco_transfers: %{ "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3" => 10.04 },
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

      assert %Contract{next_transaction: %Transaction{data: %TransactionData{content: "yes"}}} =
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

      assert %Contract{next_transaction: %Transaction{data: %TransactionData{content: "hello"}}} =
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

      assert %Contract{next_transaction: %Transaction{data: %TransactionData{content: "hello 4"}}} =
               Interpreter.execute_actions(contract, :transaction)
    end

    test "should flatten comparison operators" do
      code = """
      condition inherit: [
        secret: size() >= 10
      ]
      """

      {:ok,
       %Contract{
         conditions: %{
           inherit: %Conditions{
             secret:
               {:>=, [line: 2],
                [
                  {{:., [line: 2],
                    [
                      {:__aliases__, [alias: ArchEthic.Contracts.Interpreter.Library],
                       [:Library]},
                      :size
                    ]}, [line: 2],
                   [
                     {:get_in, [line: 2], [{:scope, [line: 2], nil}, ["next", "secret"]]}
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
        type: in?([transfer, nft]),
        content: if type == transfer do
         regex_match?("reason transfer: (.*)")
        else
         regex_match?("reason nft creation: (.*)")
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
                 "next" => %{"type" => "nft", "content" => "reason nft creation: new super token"}
               })

      assert true ==
               Interpreter.valid_conditions?(transaction_conditions, %{
                 "transaction" => %{"content" => Crypto.hash(code)},
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
          add_nft_transfer to: transaction.address, nft: contract.address, amount: token_to_credit
        end
      end
      """
      |> Interpreter.parse()
  end
end
