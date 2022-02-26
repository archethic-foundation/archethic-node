defmodule ArchEthic.TransactionChain.TransactionData.NFTLedgerTest do
  use ExUnit.Case
  use ExUnitProperties

  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger.Transfer

  doctest NFTLedger

  property "symmetric serialization/deserialization of NFT ledger" do
    check all(
            transfers <-
              StreamData.map_of(
                StreamData.binary(length: 32),
                {StreamData.binary(length: 32), StreamData.positive_integer()}
              )
          ) do
      transfers =
        Enum.map(transfers, fn {nft, {to, amount}} ->
          %Transfer{
            nft: <<0::8, 0::8>> <> nft,
            to: <<0::8, 0::8>> <> to,
            amount: amount
          }
        end)

      {nft_ledger, _} =
        %NFTLedger{transfers: transfers}
        |> NFTLedger.serialize()
        |> NFTLedger.deserialize()

      assert nft_ledger.transfers == transfers
    end
  end
end
