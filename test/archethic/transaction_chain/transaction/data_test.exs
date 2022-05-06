defmodule Archethic.TransactionChain.TransactionDataTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Archethic.Crypto

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  doctest TransactionData

  property "symmetric serialization/deserialization of transaction data" do
    check all(
            code <- StreamData.binary(),
            content <- StreamData.binary(),
            secret <- StreamData.binary(min_length: 1),
            authorized_key_seeds <-
              StreamData.list_of(StreamData.binary(length: 32), min_length: 1),
            transfers <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.positive_integer()),
            recipients <- list_of(StreamData.binary(length: 32))
          ) do
      authorized_public_keys =
        Enum.map(authorized_key_seeds, fn seed ->
          {pub, _} = Crypto.generate_deterministic_keypair(seed)
          pub
        end)

      recipients_addresses = Enum.map(recipients, &<<0::8, 0::8, &1::binary>>)

      transfers =
        Enum.map(transfers, fn {to, amount} ->
          %Transfer{to: <<0::8, 0::8, to::binary>>, amount: amount}
        end)

      {tx_data, _} =
        %TransactionData{
          code: code,
          content: content,
          ownerships: [
            Ownership.new(
              secret,
              :crypto.strong_rand_bytes(32),
              authorized_public_keys
            )
          ],
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: transfers
            }
          },
          recipients: recipients_addresses
        }
        |> TransactionData.serialize()
        |> TransactionData.deserialize()

      assert tx_data.code == code
      assert tx_data.content == content
      assert List.first(tx_data.ownerships).secret == secret

      assert Enum.all?(
               Ownership.list_authorized_public_keys(List.first(tx_data.ownerships)),
               &(&1 in authorized_public_keys)
             )

      assert tx_data.recipients == recipients_addresses
      assert tx_data.ledger.uco.transfers == transfers
    end
  end
end
