defmodule Archethic.Contracts.InterpreterTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.Contracts.Contract

  alias Archethic.Contracts.Interpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Interpreter

  describe "parse/1" do
    test "should return an error if not conditions or triggers are defined" do
      assert {:error, _} =
               """
               abc
               """
               |> Interpreter.parse()

      assert {:error, _} =
               """
               condition
               """
               |> Interpreter.parse()
    end

    test "should return an error for unexpected term" do
      assert {:error, "unexpected term - @1 - L1"} = "@1" |> Interpreter.parse()
    end
  end

  test "ICO contract parsing" do
    assert {:ok, _} =
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

  test "schedule transfers parsing" do
    assert {:ok, _} =
             """
             condition inherit: [
               type: transfer,
               uco_transfers: 
                  %{ "0000D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC" => 100000000 }
             ]

             actions triggered_by: interval, at: "* * * * *" do
               set_type transfer
               add_uco_transfer to: "0000D574D171A484F8DEAC2D61FC3F7CC984BEB52465D69B3B5F670090742CBF5CC", amount: 100000000
             end
             """
             |> Interpreter.parse()
  end
end
