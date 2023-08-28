defmodule Archethic.Contracts.Interpreter.Legacy.ActionInterpreterTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Legacy.ActionInterpreter
  alias Archethic.Contracts.Interpreter
  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetFirstTransactionAddress
  alias Archethic.P2P.Message.FirstTransactionAddress

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest ActionInterpreter

  import Mox

  test "should parse a contract with some standard functions" do
    assert {
             :ok,
             {:transaction, nil, nil},
             {
               :__block__,
               [],
               [
                 {
                   :__block__,
                   [],
                   [
                     {
                       :=,
                       [line: 2],
                       [
                         {:scope, [line: 2], nil},
                         {:update_in, [line: 2],
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
                                        Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                    ], [:TransactionStatements]},
                                   :set_type
                                 ]}, [line: 2], [{:&, [line: 2], [1]}, "transfer"]}
                             ]}
                          ]}
                       ]
                     },
                     {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                      [{:scope, [], nil}]}
                   ]
                 },
                 {
                   :__block__,
                   [],
                   [
                     {
                       :=,
                       [line: 3],
                       [
                         {:scope, [line: 3], nil},
                         {:update_in, [line: 3],
                          [
                            {:scope, [line: 3], nil},
                            ["next_transaction"],
                            {:&, [line: 3],
                             [
                               {{:., [line: 3],
                                 [
                                   {:__aliases__,
                                    [
                                      alias:
                                        Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                    ], [:TransactionStatements]},
                                   :add_uco_transfer
                                 ]}, [line: 3],
                                [
                                  {:&, [line: 3], [1]},
                                  [
                                    {"to",
                                     "7F6661ACE282F947ACA2EF947D01BDDC90C65F09EE828BDADE2E3ED4258470B3"},
                                    {"amount", 1_040_000_000}
                                  ]
                                ]}
                             ]}
                          ]}
                       ]
                     },
                     {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                      [{:scope, [], nil}]}
                   ]
                 },
                 {
                   :__block__,
                   [],
                   [
                     {
                       :=,
                       [line: 4],
                       [
                         {:scope, [line: 4], nil},
                         {:update_in, [line: 4],
                          [
                            {:scope, [line: 4], nil},
                            ["next_transaction"],
                            {:&, [line: 4],
                             [
                               {{:., [line: 4],
                                 [
                                   {:__aliases__,
                                    [
                                      alias:
                                        Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                    ], [:TransactionStatements]},
                                   :add_token_transfer
                                 ]}, [line: 4],
                                [
                                  {:&, [line: 4], [1]},
                                  [
                                    {"to",
                                     "30670455713E2CBECF94591226A903651ED8625635181DDA236FECC221D1E7E4"},
                                    {"amount", 20_000_000_000},
                                    {"token_address",
                                     "AEB4A6F5AB6D82BE223C5867EBA5FE616F52F410DCF83B45AFF158DD40AE8AC3"},
                                    {"token_id", 0}
                                  ]
                                ]}
                             ]}
                          ]}
                       ]
                     },
                     {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                      [{:scope, [], nil}]}
                   ]
                 },
                 {
                   :__block__,
                   [],
                   [
                     {
                       :=,
                       [line: 5],
                       [
                         {:scope, [line: 5], nil},
                         {:update_in, [line: 5],
                          [
                            {:scope, [line: 5], nil},
                            ["next_transaction"],
                            {:&, [line: 5],
                             [
                               {{:., [line: 5],
                                 [
                                   {:__aliases__,
                                    [
                                      alias:
                                        Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                    ], [:TransactionStatements]},
                                   :set_content
                                 ]}, [line: 5], [{:&, [line: 5], [1]}, "Receipt"]}
                             ]}
                          ]}
                       ]
                     },
                     {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                      [{:scope, [], nil}]}
                   ]
                 },
                 {
                   :__block__,
                   [],
                   [
                     {
                       :=,
                       [line: 6],
                       [
                         {:scope, [line: 6], nil},
                         {:update_in, [line: 6],
                          [
                            {:scope, [line: 6], nil},
                            ["next_transaction"],
                            {:&, [line: 6],
                             [
                               {{:., [line: 6],
                                 [
                                   {:__aliases__,
                                    [
                                      alias:
                                        Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                    ], [:TransactionStatements]},
                                   :add_ownership
                                 ]}, [line: 6],
                                [
                                  {:&, [line: 6], [1]},
                                  [
                                    {"secret", "MyEncryptedSecret"},
                                    {"secret_key", "MySecretKey"},
                                    {"authorized_public_keys",
                                     [
                                       "70C245E5D970B59DF65638BDD5D963EE22E6D892EA224D8809D0FB75D0B1907A"
                                     ]}
                                  ]
                                ]}
                             ]}
                          ]}
                       ]
                     },
                     {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                      [{:scope, [], nil}]}
                   ]
                 },
                 {
                   :__block__,
                   [],
                   [
                     {
                       :=,
                       [line: 7],
                       [
                         {:scope, [line: 7], nil},
                         {:update_in, [line: 7],
                          [
                            {:scope, [line: 7], nil},
                            ["next_transaction"],
                            {:&, [line: 7],
                             [
                               {{:., [line: 7],
                                 [
                                   {:__aliases__,
                                    [
                                      alias:
                                        Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                    ], [:TransactionStatements]},
                                   :add_recipient
                                 ]}, [line: 7],
                                [
                                  {:&, [line: 7], [1]},
                                  "78273C5CBCEB8617F54380CC2F173DF2404DB676C9F10D546B6F395E6F3BDDEE"
                                ]}
                             ]}
                          ]}
                       ]
                     },
                     {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
                      [{:scope, [], nil}]}
                   ]
                 }
               ]
             }
           } =
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
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
  end

  test "should evaluate actions based on if statement" do
    assert %Transaction{data: %TransactionData{content: "yes"}} =
             ~S"""
             actions triggered_by: transaction do
               if transaction.previous_public_key == "abc" do
                 set_content "yes"
               else
                 set_content "no"
               end
             end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute(%{"transaction" => %{"previous_public_key" => "abc"}})
  end

  test "should use a variable assignation" do
    assert %Transaction{data: %TransactionData{content: "hello"}} =
             """
               actions triggered_by: transaction do
                 new_content = \"hello\"
                 set_content new_content
               end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  test "should use a interpolation assignation" do
    assert %Transaction{data: %TransactionData{content: "hello 4"}} =
             ~S"""
               actions triggered_by: transaction do
                 new_content = "hello #{2+2}"
                 set_content new_content
               end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  test "shall use get_genesis_address/1 in actions" do
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

    # seed for replacement address 64F05F5236088FC64D1BB19BD13BC548F1C49A42432AF02AD9024D8A2990B2B4
    address = "000077003155E556981870BAEA665910C98679AE501598D11640FE37F58F72B3F06F"
    b_address = Base.decode16!(address)

    MockClient
    |> expect(:send_message, fn _, _, _ ->
      {:ok, %GenesisAddress{address: b_address, timestamp: DateTime.utc_now()}}
    end)

    assert %Transaction{data: %TransactionData{content: "yes"}} =
             ~s"""
             actions triggered_by: transaction do
               address = get_genesis_address("000077003155E556981870BAEA665910C98679AE501598D11640FE37F58F72B3F06F")
               if address == "000077003155E556981870BAEA665910C98679AE501598D11640FE37F58F72B3F06F" do
                 set_content "yes"
               else
                 set_content "no"
               end
             end
             """
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  describe "Hash in action" do
    test "Hash/2 blake2b" do
      assert %Transaction{data: %TransactionData{content: "yes"}} =
               ~s"""
               actions triggered_by: transaction do
                 address = hash("hello darkness ","blake2b")
                 if address == "CCFF7E67D673C76E3AAA242BF6B726DD75EF1C5AA201A527CFC76754B23AE0EAF83960DFC9377C4EDA7CF25EF3A9D0E66B54A3993F8AC2ECB5CA9CBDB79454F7" do
                   set_content "yes"
                 else
                   set_content "no"
                 end
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
               |> elem(2)
               |> ActionInterpreter.execute()
    end

    test "Hash/1" do
      assert %Transaction{data: %TransactionData{content: "yes"}} =
               ~s"""
               actions triggered_by: transaction do
                 address = hash("hello darkness ")
                 if address == "E96FC07DD7B9EE9CDA01DF26DC9AFA78388EB33B12FDB8619C27BEAA3130CF18" do
                   set_content "yes"
                 else
                   set_content "no"
                 end
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
               |> elem(2)
               |> ActionInterpreter.execute()
    end
  end

  test "Use get_first_transaction_address/1 in actions" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    first_address_bin =
      "some random seed" |> Crypto.derive_keypair(0) |> elem(0) |> Crypto.derive_address()

    second_address_bin =
      "some random seed" |> Crypto.derive_keypair(1) |> elem(0) |> Crypto.derive_address()

    first_addr = first_address_bin |> Base.encode16()
    second_addr = second_address_bin |> Base.encode16()

    MockClient
    |> stub(:send_message, fn
      _, %GetFirstTransactionAddress{address: ^first_address_bin}, _ ->
        {:ok,
         %FirstTransactionAddress{
           address: second_address_bin,
           timestamp: DateTime.utc_now()
         }}

      _, _, _ ->
        {:error, :network_error}
    end)

    contract_code = ~s"""
    actions triggered_by: transaction do
      address = get_first_transaction_address("#{first_addr}")
      if address == "#{second_addr}" do
        set_content "first_address_acquired"
      else
        set_content "not_acquired"
      end
    end
    """

    assert %Transaction{data: %TransactionData{content: "first_address_acquired"}} =
             contract_code
             |> Interpreter.sanitize_code()
             |> elem(1)
             |> ActionInterpreter.parse()
             |> elem(2)
             |> ActionInterpreter.execute()
  end

  describe "blacklist" do
    test "should parse when arguments are allowed" do
      assert {:ok, {:transaction, nil, nil}, _ast} =
               ~S"""
               actions triggered_by: transaction do
                 add_uco_transfer to: "ABC123", amount: 64
                 add_token_transfer to: "ABC123", amount: 64, token_id: 0, token_address: "012"
                 add_ownership secret: "ABC123", secret_key: "s3cr3t", authorized_public_keys: ["ADE459"]
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should parse when arguments are variables" do
      assert {:ok, {:transaction, nil, nil}, _ast} =
               ~S"""
               actions triggered_by: transaction do
                 address = "ABC123"
                 add_uco_transfer to: address, amount: 64
                 add_token_transfer to: address, amount: 64, token_id: 0, token_address: "012"
                 add_ownership secret: address, secret_key: "s3cr3t", authorized_public_keys: ["ADE459"]
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should parse when arguments are fields" do
      assert {:ok, {:transaction, nil, nil}, _ast} =
               ~S"""
               actions triggered_by: transaction do
                 add_uco_transfer to: transaction.address, amount: 64
                 add_token_transfer to: transaction.address, amount: 64, token_id: 0, token_address: "012"
                 add_ownership secret: transaction.address, secret_key: "s3cr3t", authorized_public_keys: ["ADE459"]
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should parse when arguments are functions" do
      assert {:ok, {:transaction, nil, nil}, _ast} =
               ~S"""
               actions triggered_by: transaction do
                 add_uco_transfer to: regex_extract("@addr", ".*"), amount: 64
                 add_token_transfer to: regex_extract("@addr", ".*"), amount: 64, token_id: 0, token_address: "012"
                 add_ownership secret: regex_extract("@addr", ".*"), secret_key: "s3cr3t", authorized_public_keys: ["ADE459"]
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should parse when arguments are string interpolation" do
      assert {:ok, {:transaction, nil, nil}, _ast} =
               ~S"""
               actions triggered_by: transaction do
                 name = "sophia"
                 add_uco_transfer to: "hello #{name}", amount: 64
                 add_token_transfer to: "hello #{name}", amount: 64, token_id: 0, token_address: "012"
                 add_ownership secret: "hello #{name}", secret_key: "s3cr3t", authorized_public_keys: ["ADE459"]
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should parse when building a keyword list" do
      assert {:ok, {:transaction, nil, nil}, _ast} =
               ~S"""
               actions triggered_by: transaction do
                 uco_transfer = [to: "ABC123", amount: 33]
                 add_uco_transfer uco_transfer

                 token_transfer = [to: "ABC123", amount: 64, token_id: 0, token_address: "012"]
                 add_token_transfer token_transfer

                 ownership = [secret: "ABC123", secret_key: "s3cr3t", authorized_public_keys: ["ADE459"]]
                 add_ownership ownership
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end

    test "should not parse when arguments are not allowed" do
      assert {:error, "invalid add_uco_transfer arguments - amount"} =
               ~S"""
               actions triggered_by: transaction do
                 add_uco_transfer to: "abc123", amount: 0
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      assert {:error, "invalid add_uco_transfer arguments - hello"} =
               ~S"""
               actions triggered_by: transaction do
                 add_uco_transfer to: "abc123", amount: 31, hello: 1
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      assert {:error, "invalid add_token_transfer arguments - amount"} =
               ~S"""
               actions triggered_by: transaction do
                add_token_transfer to: "abc123", amount: "thirty one"
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()

      assert {:error, "invalid add_ownership arguments - authorized_public_keys"} =
               ~S"""
               actions triggered_by: transaction do
                add_ownership secret: "ABC123", secret_key: "s3cr3t", authorized_public_keys: 42
               end
               """
               |> Interpreter.sanitize_code()
               |> elem(1)
               |> ActionInterpreter.parse()
    end
  end
end
