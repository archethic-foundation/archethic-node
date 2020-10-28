defmodule Uniris.TransactionChain.TransactionData.UCOLedgerTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Uniris.TransactionChain.TransactionData.Ledger.Transfer
  alias Uniris.TransactionChain.TransactionData.UCOLedger

  doctest UCOLedger

  property "symmetric serialization/deserialization of uco ledger" do
    check all(
            transfers <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.float(min: 0.0))
          ) do
      transfers =
        Enum.map(transfers, fn {to, amount} ->
          %Transfer{
            to: <<0::8>> <> to,
            amount: amount
          }
        end)

      {uco_ledger, _} =
        %UCOLedger{transfers: transfers}
        |> UCOLedger.serialize()
        |> UCOLedger.deserialize()

      assert uco_ledger.transfers == transfers
    end
  end
end
