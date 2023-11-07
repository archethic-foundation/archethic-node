defmodule Archethic.Contracts.Interpreter.Library.Common.TokenTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Token

  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Utils

  import Mox

  doctest Token

  # ----------------------------------------
  describe "fetch_id_from_address/1" do
    test "should work" do
      seed = "s3cr3t"
      {genesis_pub_key, _} = Crypto.generate_deterministic_keypair(seed)
      genesis_address = Crypto.derive_address(genesis_pub_key)

      {pub_key, _} = Crypto.derive_keypair(seed, 24)
      token_address = Crypto.derive_address(pub_key)

      code = ~s"""
      actions triggered_by: transaction do
        id = Token.fetch_id_from_address("#{Base.encode16(token_address)}")
        Contract.set_content id
      end
      """

      tx =
        Transaction.new(
          :token,
          %TransactionData{
            content:
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
          },
          seed,
          0
        )

      MockDB
      |> expect(:get_genesis_address, fn ^token_address -> genesis_address end)
      |> stub(:get_transaction, fn ^token_address, _, _ -> {:ok, tx} end)

      {:ok, %{id: token_id}} = Utils.get_token_properties(genesis_address, tx)

      assert {%Transaction{data: %TransactionData{content: content}}, _state} =
               sanitize_parse_execute(code)

      assert content == token_id
    end
  end
end
