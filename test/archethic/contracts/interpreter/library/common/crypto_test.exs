defmodule Archethic.Contracts.Interpreter.Library.Common.CryptoTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Crypto

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Crypto

  # ----------------------------------------
  describe "hash/1" do
    test "should work without algo" do
      text = "wu-tang"

      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Crypto.hash("#{text}")
      end
      """

      assert %Transaction{data: %TransactionData{content: content}} = sanitize_parse_execute(code)
      assert content == Base.encode16(:crypto.hash(:sha256, text))
    end
  end

  describe "hash/2" do
    test "should work with algo" do
      text = "wu-tang"

      code = ~s"""
      actions triggered_by: transaction do
        Contract.set_content Crypto.hash("#{text}", "sha512")
      end
      """

      assert %Transaction{data: %TransactionData{content: content}} = sanitize_parse_execute(code)
      assert content == Base.encode16(:crypto.hash(:sha512, text))
    end
  end
end
