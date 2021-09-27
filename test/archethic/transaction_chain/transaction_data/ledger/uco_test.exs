defmodule ArchEthic.TransactionChain.TransactionData.UCOLedgerTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer

  doctest UCOLedger

  property "symmetric serialization/deserialization of uco ledger" do
    check all(
            transfers <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.positive_integer())
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
