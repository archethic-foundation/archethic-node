defmodule Archethic.Contracts.ContractTest do
  @moduledoc false

  alias Archethic.Contracts.Contract
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  use ArchethicCase
  import ArchethicCase

  describe "get_args_names_for_recipient/2" do
    test "should return args names" do
      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: """
          @version 1
          condition transaction, on: vote(candidate), as: []
          actions triggered_by: transaction, on: vote(candidate) do
            Contract.set_content candidate
          end
          """
        }
      }

      assert ["candidate"] =
               Contract.get_args_names_for_recipient(
                 Contract.from_transaction!(contract_tx),
                 %Recipient{
                   address: contract_tx.address,
                   action: "vote",
                   args: ["Julio"]
                 }
               )
    end

    test "should return nil when named action does not exist" do
      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: """
          @version 1
          condition inherit: []
          """
        }
      }

      assert nil ==
               Contract.get_args_names_for_recipient(
                 Contract.from_transaction!(contract_tx),
                 %Recipient{
                   address: contract_tx.address,
                   action: "vote",
                   args: ["Julio"]
                 }
               )
    end

    test "should return nil when arity is not correct" do
      contract_tx = %Transaction{
        type: :contract,
        address: random_address(),
        data: %TransactionData{
          code: """
          @version 1
          condition transaction, on: vote(candidate), as: []
          actions triggered_by: transaction, on: vote(candidate) do
            Contract.set_content candidate
          end
          """
        }
      }

      assert nil ==
               Contract.get_args_names_for_recipient(
                 Contract.from_transaction!(contract_tx),
                 %Recipient{
                   address: contract_tx.address,
                   action: "vote",
                   args: ["Dr. Pepper", "Dr. Dre"]
                 }
               )
    end
  end
end
