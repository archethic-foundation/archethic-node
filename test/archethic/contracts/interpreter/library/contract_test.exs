defmodule Archethic.Contracts.Interpreter.Library.ContractTest do
  @moduledoc """
  Here we test the contract module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase

  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionInterpreter
  alias Archethic.Contracts.Interpreter.Library.Contract

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  doctest Contract

  # ----------------------------------------
  describe "set_type/2" do
    test "should set the type of the contract" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_type "transfer"
      end
      """

      assert %Transaction{type: :transfer} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_type "contract"
      end
      """

      assert %Transaction{type: :contract} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        variable = "transfer"
        Contract.set_type variable
      end
      """

      assert %Transaction{type: :transfer} = sanitize_parse_execute(code)
    end

    test "should not parse if the type is unknown" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_type "invalid"
      end
      """

      assert {:error, _, _} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "set_content/2" do
    test "should work with binary" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      assert %Transaction{data: %TransactionData{content: "hello"}} = sanitize_parse_execute(code)
    end

    test "should work with integer" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content 12
      end
      """

      assert %Transaction{data: %TransactionData{content: "12"}} = sanitize_parse_execute(code)
    end

    test "should work with float" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content 13.1
      end
      """

      assert %Transaction{data: %TransactionData{content: "13.1"}} = sanitize_parse_execute(code)

      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_content 13.0
      end
      """

      assert %Transaction{data: %TransactionData{content: "13"}} = sanitize_parse_execute(code)
    end

    test "should work with variable" do
      code = ~S"""
      actions triggered_by: transaction do
        value = "foo"
        Contract.set_content value
      end
      """

      assert %Transaction{data: %TransactionData{content: "foo"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "set_code/2" do
    test "should work with binary" do
      code = ~S"""
      actions triggered_by: transaction do
        Contract.set_code "hello"
      end
      """

      assert %Transaction{data: %TransactionData{code: "hello"}} = sanitize_parse_execute(code)
    end

    test "should work with variable" do
      code = ~S"""
      actions triggered_by: transaction do
        value = "foo"
        Contract.set_code value
      end
      """

      assert %Transaction{data: %TransactionData{code: "foo"}} = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_uco_transfer/2" do
    test "should work with keyword" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_uco_transfer(to: "#{Base.encode16(address)}", amount: 9000)
      end
      """

      expected_amount = Archethic.Utils.to_bigint(9000)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   uco: %UCOLedger{
                     transfers: [
                       %UCOTransfer{amount: ^expected_amount, to: ^address}
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end

    test "should work with variable" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = [to: "#{Base.encode16(address)}", amount: 9000]
        Contract.add_uco_transfer transfer
      end
      """

      expected_amount = Archethic.Utils.to_bigint(9000)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   uco: %UCOLedger{
                     transfers: [
                       %UCOTransfer{amount: ^expected_amount, to: ^address}
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_token_transfer/2" do
    test "should work with keyword" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_token_transfer(to: "#{Base.encode16(address)}", amount: 14, token_address: "#{Base.encode16(token_address)}")
      end
      """

      expected_amount = Archethic.Utils.to_bigint(14)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   token: %TokenLedger{
                     transfers: [
                       %TokenTransfer{
                         to: ^address,
                         amount: ^expected_amount,
                         token_address: ^token_address,
                         token_id: 0
                       }
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end

    test "should work with variable" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = [to: "#{Base.encode16(address)}", amount: 15, token_id: 1, token_address: "#{Base.encode16(token_address)}"]
        Contract.add_token_transfer transfer
      end
      """

      expected_amount = Archethic.Utils.to_bigint(15)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   token: %TokenLedger{
                     transfers: [
                       %TokenTransfer{
                         to: ^address,
                         amount: ^expected_amount,
                         token_address: ^token_address,
                         token_id: 1
                       }
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_recipient/2" do
    test "should work with keyword" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_recipient("#{Base.encode16(address)}")
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [^address]
               }
             } = sanitize_parse_execute(code)
    end

    test "should work when called multiple times" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_recipient("#{Base.encode16(address)}")
        Contract.add_recipient("#{Base.encode16(address2)}")
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [^address2, ^address]
               }
             } = sanitize_parse_execute(code)
    end

    test "should work with variable" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = "#{Base.encode16(address)}"
        Contract.add_recipient transfer
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [^address]
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_ownership/2" do
    test "should work with keyword" do
      {pub_key1, _} = Archethic.Crypto.generate_deterministic_keypair("seed")

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_ownership(secret: "ENCODED_SECRET1", authorized_public_keys: ["#{Base.encode16(pub_key1)}"], secret_key: "___")
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 ownerships: [
                   %Ownership{
                     authorized_keys: %{
                       ^pub_key1 => _
                     },
                     secret: "ENCODED_SECRET1"
                   }
                 ]
               }
             } = sanitize_parse_execute(code)
    end

    test "should work when called multiple times" do
      {pub_key1, _} = Archethic.Crypto.generate_deterministic_keypair("seed")
      {pub_key2, _} = Archethic.Crypto.generate_deterministic_keypair("seed2")

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_ownership(secret: "ENCODED_SECRET1", authorized_public_keys: ["#{Base.encode16(pub_key1)}"], secret_key: "___")
        Contract.add_ownership(secret: "ENCODED_SECRET2", authorized_public_keys: ["#{Base.encode16(pub_key2)}"], secret_key: "___")
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 ownerships: [
                   %Ownership{
                     authorized_keys: %{
                       ^pub_key2 => _
                     },
                     secret: "ENCODED_SECRET2"
                   },
                   %Ownership{
                     authorized_keys: %{
                       ^pub_key1 => _
                     },
                     secret: "ENCODED_SECRET1"
                   }
                 ]
               }
             } = sanitize_parse_execute(code)
    end

    test "should work with variable" do
      {pub_key1, _} = Archethic.Crypto.generate_deterministic_keypair("seed")

      code = ~s"""
      actions triggered_by: transaction do
        ownership = [secret: "ENCODED_SECRET1", authorized_public_keys: ["#{Base.encode16(pub_key1)}"], secret_key: "___"]
        Contract.add_ownership(ownership)
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 ownerships: [
                   %Ownership{
                     authorized_keys: %{
                       ^pub_key1 => _
                     },
                     secret: "ENCODED_SECRET1"
                   }
                 ]
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_uco_transfers/2" do
    test "should work" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfers = [
          [to: "#{Base.encode16(address)}", amount: 1234],
          [to: "#{Base.encode16(address2)}", amount: 5678]
        ]
        Contract.add_uco_transfers(transfers)
      end
      """

      expected_amount1 = Archethic.Utils.to_bigint(1234)
      expected_amount2 = Archethic.Utils.to_bigint(5678)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   uco: %UCOLedger{
                     transfers: [
                       %UCOTransfer{amount: ^expected_amount2, to: ^address2},
                       %UCOTransfer{amount: ^expected_amount1, to: ^address}
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_token_transfers/2" do
    test "should work" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfers = [
          [to: "#{Base.encode16(address)}", amount: 14, token_address: "#{Base.encode16(token_address)}"],
          [to: "#{Base.encode16(address2)}", amount: 3,token_id: 4, token_address: "#{Base.encode16(token_address)}"]
        ]
        Contract.add_token_transfers(transfers)
      end
      """

      expected_amount1 = Archethic.Utils.to_bigint(14)
      expected_amount2 = Archethic.Utils.to_bigint(3)

      assert %Transaction{
               data: %TransactionData{
                 ledger: %Ledger{
                   token: %TokenLedger{
                     transfers: [
                       %TokenTransfer{
                         to: ^address2,
                         amount: ^expected_amount2,
                         token_address: ^token_address,
                         token_id: 4
                       },
                       %TokenTransfer{
                         to: ^address,
                         amount: ^expected_amount1,
                         token_address: ^token_address,
                         token_id: 0
                       }
                     ]
                   }
                 }
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_recipients/2" do
    test "should work" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        recipients = ["#{Base.encode16(address)}", "#{Base.encode16(address2)}"]
        Contract.add_recipients(recipients)
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [^address2, ^address]
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "add_ownerships/2" do
    test "should work" do
      {pub_key1, _} = Archethic.Crypto.generate_deterministic_keypair("seed")
      {pub_key2, _} = Archethic.Crypto.generate_deterministic_keypair("seed2")

      code = ~s"""
      actions triggered_by: transaction do
        ownerships = [
          [secret: "ENCODED_SECRET1", authorized_public_keys: ["#{Base.encode16(pub_key1)}"], secret_key: "___"],
          [secret: "ENCODED_SECRET2", authorized_public_keys: ["#{Base.encode16(pub_key2)}"], secret_key: "___"]
        ]
        Contract.add_ownerships(ownerships)
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 ownerships: [
                   %Ownership{
                     authorized_keys: %{
                       ^pub_key2 => _
                     },
                     secret: "ENCODED_SECRET2"
                   },
                   %Ownership{
                     authorized_keys: %{
                       ^pub_key1 => _
                     },
                     secret: "ENCODED_SECRET1"
                   }
                 ]
               }
             } = sanitize_parse_execute(code)
    end
  end

  # ----------------------------------------
  describe "get_calls/1" do
    test "should work" do
      contract_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        calls = Contract.get_calls()
        Contract.set_content List.size(calls)
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 content: "2"
               }
             } =
               sanitize_parse_execute(code, %{
                 "calls" => [
                   Constants.from_transaction(%Transaction{
                     data: %TransactionData{},
                     address: <<0::16, :crypto.strong_rand_bytes(32)::binary>>
                   }),
                   Constants.from_transaction(%Transaction{
                     data: %TransactionData{},
                     address: <<0::16, :crypto.strong_rand_bytes(32)::binary>>
                   })
                 ],
                 "contract" =>
                   Constants.from_transaction(%Transaction{
                     data: %TransactionData{},
                     address: contract_address
                   })
               })
    end
  end

  defp sanitize_parse_execute(code, constants \\ %{}) do
    with {:ok, sanitized_code} <- Interpreter.sanitize_code(code),
         {:ok, _, action_ast} <- ActionInterpreter.parse(sanitized_code) do
      ActionInterpreter.execute(action_ast, constants)
    end
  end
end
