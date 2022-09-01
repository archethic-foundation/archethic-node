defmodule Archethic.TransactionChain.TransactionData.TokenLedgerTest do
  @moduledoc false
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer

  doctest TokenLedger

  property "symmetric serialization/deserialization of token ledger" do
    check all(
            transfers <-
              StreamData.map_of(
                StreamData.binary(length: 32),
                {StreamData.binary(length: 32), StreamData.positive_integer(),
                 StreamData.positive_integer()}
              )
          ) do
      transfers =
        Enum.map(transfers, fn {token, {to, amount, token_id}} ->
          %Transfer{
            token_address: <<0::8, 0::8>> <> token,
            to: <<0::8, 0::8>> <> to,
            amount: amount,
            token_id: token_id
          }
        end)

      {token_ledger, _} =
        %TokenLedger{transfers: transfers}
        |> TokenLedger.serialize()
        |> TokenLedger.deserialize()

      assert token_ledger.transfers == transfers
    end
  end
end
