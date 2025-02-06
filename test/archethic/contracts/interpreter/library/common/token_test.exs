defmodule Archethic.Contracts.Interpreter.Library.Common.TokenTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Token

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  alias Archethic.TransactionFactory

  import Mox

  doctest Token

  describe "fetch_id_from_address/1" do
    test "should work" do
      content =
        Jason.encode!(%{
          supply: 300_000_000,
          name: "MyToken",
          type: "non-fungible",
          symbol: "MTK",
          properties: %{
            global: "property"
          },
          collection: [
            %{image: "link", value: "link"},
            %{image: "link", value: "link"},
            %{image: "link", value: "link"}
          ]
        })

      tx =
        %Transaction{address: token_address} =
        TransactionFactory.create_valid_transaction([], content: content, type: :token, index: 24)

      MockDB
      |> stub(:get_transaction, fn ^token_address, _, _ -> {:ok, tx} end)

      {:ok, %{id: token_id}} = Utils.get_token_properties(tx)

      code = ~s"""
      actions triggered_by: transaction do
      id = Token.fetch_id_from_address("#{Base.encode16(token_address)}")
      Contract.set_content id
      end
      """

      assert {%Transaction{data: %TransactionData{content: content}}, _state} =
               sanitize_parse_execute(code)

      assert content == token_id
    end
  end
end
