defmodule Uniris.Contracts.InterpreterTest do
  use ExUnit.Case

  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Conditions
  alias Uniris.Contracts.Contract.Constants
  alias Uniris.Contracts.Contract.Trigger

  alias Uniris.Contracts.Interpreter

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  doctest Interpreter

  test "parse/1 should parse a contract with some standard functions" do
    assert {:ok,
            %Contract{
              triggers: [
                %Trigger{
                  type: :transaction,
                  actions:
                    {:__block__, [],
                     [
                       {:set_type, [line: 2], [{:transfer, [line: 2], nil}]},
                       {:add_uco_transfer, [line: 3],
                        [
                          [
                            to:
                              "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3",
                            amount: 10.04
                          ]
                        ]},
                       {:add_nft_transfer, [line: 4],
                        [
                          [
                            to:
                              "30670455713E2CBECF94591226A903651ED8625635181DDA236FECC221D1E7E4",
                            amount: 200.0,
                            nft:
                              "AEB4A6F5AB6D82BE223C5867EBA5FE616F52F410DCF83B45AFF158DD40AE8AC3"
                          ]
                        ]},
                       {:set_content, [line: 5], ["Receipt"]},
                       {:set_secret, [line: 6], ["MyEncryptedSecret"]},
                       {:add_authorized_key, [line: 7],
                        [
                          [
                            public_key:
                              "70C245E5D970B59DF65638BDD5D963EE22E6D892EA224D8809D0FB75D0B1907A",
                            encrypted_secret_key:
                              "47442AFD338F83BDDCDE9CF2AEDD69B0213E7F956E202769E290F0E2695E9351"
                          ]
                        ]},
                       {:add_recipient, [line: 8],
                        ["78273C5CBCEB8617F54380CC2F173DF2404DB676C9F10D546B6F395E6F3BDDEE"]}
                     ]}
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

  test "execute_inherit_condition/2 should execute code and call library functions with the inherit condition subject " do
    code = "regex_match?(\"hello\")"
    assert false == Interpreter.execute_inherit_condition(code, "abc")

    code = "regex_match?(\"hello\")"
    assert true == Interpreter.execute_inherit_condition(code, "hello")

    code = "regex_match?(\"hello\") and hash() == \"abc\" "
    assert false == Interpreter.execute_inherit_condition(code, "hello")
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
               Interpreter.execute_actions(contract, :transaction,
                 transaction: %{previous_public_key: "abc"}
               )
    end
  end
end
