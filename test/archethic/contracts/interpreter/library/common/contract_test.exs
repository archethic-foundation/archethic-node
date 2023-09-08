defmodule Archethic.Contracts.Interpreter.Library.ContractTest do
  @moduledoc """
  Here we test the contract module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Contract

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.LastTransactionAddress

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias Archethic.ContractFactory

  import Mox

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

    test "should crash if the amount is 0" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = [to: "#{Base.encode16(address)}", amount: 0]
        Contract.add_uco_transfer transfer
      end
      """

      assert_raise(ArgumentError, fn -> sanitize_parse_execute(code) end)
    end

    test "should crash if the amount is negative" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = [to: "#{Base.encode16(address)}", amount: -0.1]
        Contract.add_uco_transfer transfer
      end
      """

      assert_raise(ArgumentError, fn -> sanitize_parse_execute(code) end)
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

    test "should crash if the amount is 0" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = [to: "#{Base.encode16(address)}", amount: 0, token_id: 1, token_address: "#{Base.encode16(token_address)}"]
        Contract.add_token_transfer transfer
      end
      """

      assert_raise(ArgumentError, fn -> sanitize_parse_execute(code) end)
    end

    test "should crash if the amount is negative" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      token_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        transfer = [to: "#{Base.encode16(address)}", amount: -3, token_id: 1, token_address: "#{Base.encode16(token_address)}"]
        Contract.add_token_transfer transfer
      end
      """

      assert_raise(ArgumentError, fn -> sanitize_parse_execute(code) end)
    end
  end

  # ----------------------------------------
  describe "add_recipient/2" do
    test "should work with a base16 address" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        Contract.add_recipient("#{Base.encode16(address)}")
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [%Recipient{address: ^address}]
               }
             } = sanitize_parse_execute(code)
    end

    test "should work with a recipient struct" do
      address = random_address()

      code = ~s"""
      actions triggered_by: transaction do
        recipient = [address: "#{Base.encode16(address)}", action: "vote", args: ["Mr. Zero"]]
        Contract.add_recipient(recipient)
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [
                   %Recipient{
                     address: ^address,
                     action: "vote",
                     args: ["Mr. Zero"]
                   }
                 ]
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
                 recipients: [
                   %Recipient{address: ^address2},
                   %Recipient{address: ^address}
                 ]
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
                 recipients: [%Recipient{address: ^address}]
               }
             } = sanitize_parse_execute(code)
    end

    test "should fail when recipient is invalid" do
      address = random_address()

      code = ~s"""
      actions triggered_by: transaction do
        recipient = [address: "#{Base.encode16(address)}", args: ["Mr. Zero"]]
        Contract.add_recipient(recipient)
      end
      """

      assert_raise(RuntimeError, fn ->
        sanitize_parse_execute(code)
      end)
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
                   },
                   # Contract seed
                   %Ownership{}
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
                   },
                   # Contract seed
                   %Ownership{}
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
                   },
                   # Contract seed
                   %Ownership{}
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
          [to: "#{Base.encode16(address)}", amount: 12.34],
          [to: "#{Base.encode16(address2)}", amount: 567.8]
        ]
        Contract.add_uco_transfers(transfers)
      end
      """

      expected_amount1 = Archethic.Utils.to_bigint(12.34)
      expected_amount2 = Archethic.Utils.to_bigint(567.8)

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
          [to: "#{Base.encode16(address)}", amount: 14.1864, token_address: "#{Base.encode16(token_address)}"],
          [to: "#{Base.encode16(address2)}", amount: 3,token_id: 4, token_address: "#{Base.encode16(token_address)}"]
        ]
        Contract.add_token_transfers(transfers)
      end
      """

      expected_amount1 = Archethic.Utils.to_bigint(14.1864)
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
    test "should work with binaries" do
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
                 recipients: [
                   %Recipient{address: ^address2},
                   %Recipient{address: ^address}
                 ]
               }
             } = sanitize_parse_execute(code)
    end

    test "should work with mix of structs & binaries" do
      address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      code = ~s"""
      actions triggered_by: transaction do
        recipients = [
          [address: "#{Base.encode16(address)}", action: "vote", args: ["Mr. Zero"]],
          "#{Base.encode16(address2)}"
        ]
        Contract.add_recipients(recipients)
      end
      """

      assert %Transaction{
               data: %TransactionData{
                 recipients: [
                   %Recipient{address: ^address2},
                   %Recipient{
                     address: ^address,
                     action: "vote",
                     args: ["Mr. Zero"]
                   }
                 ]
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
                   },
                   # Contract seed
                   %Ownership{}
                 ]
               }
             } = sanitize_parse_execute(code)
    end
  end

  describe "call_function/3" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        network_patch: "AAA",
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now()
      })

      code = """
      @version 1

      export fun add(x, y) do
        x + y
      end
      """

      contract_tx = ContractFactory.create_valid_contract_tx(code)

      %{contract_tx: contract_tx}
    end

    test "should call a contract function and return it's value", %{contract_tx: contract_tx} do
      MockClient
      |> expect(:send_message, fn _, %GetLastTransactionAddress{}, _ ->
        {:ok, %LastTransactionAddress{address: contract_tx.address}}
      end)
      |> expect(:send_message, fn _, %GetTransaction{}, _ ->
        {:ok, contract_tx}
      end)

      assert 3 == contract_tx.address |> Base.encode16() |> Contract.call_function("add", [1, 2])
    end

    test "should raise an error if parameters are invalid", %{contract_tx: contract_tx} do
      assert_raise(RuntimeError, fn ->
        Contract.call_function(:invalid, "add", [1, 2])
      end)

      assert_raise(Library.Error, fn ->
        contract_tx.address |> Base.encode16() |> Contract.call_function(:invalid, [1, 2])
      end)

      assert_raise(Library.Error, fn ->
        contract_tx.address |> Base.encode16() |> Contract.call_function("add", :invalid)
      end)
    end

    test "should raise an error on network issue", %{contract_tx: contract_tx} do
      assert_raise(Library.Error, fn ->
        contract_tx.address |> Base.encode16() |> Contract.call_function("add", [1, 2])
      end)
    end

    test "should raise an error if function does not exists", %{contract_tx: contract_tx} do
      MockClient
      |> stub(:send_message, fn
        _, %GetLastTransactionAddress{}, _ ->
          {:ok, %LastTransactionAddress{address: contract_tx.address}}

        _, %GetTransaction{}, _ ->
          {:ok, contract_tx}
      end)

      assert_raise(Library.Error, fn ->
        contract_tx.address |> Base.encode16() |> Contract.call_function("add", [1, 2, 3])
      end)

      assert_raise(Library.Error, fn ->
        contract_tx.address |> Base.encode16() |> Contract.call_function("not_exists", [1, 2])
      end)
    end
  end
end
