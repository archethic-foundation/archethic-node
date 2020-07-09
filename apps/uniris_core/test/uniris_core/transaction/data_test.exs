defmodule UnirisCore.TransactionDataTest do
  use ExUnit.Case
  use ExUnitProperties

  alias UnirisCore.Crypto

  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.TransactionData.UCOLedger

  doctest TransactionData

  property "symmetric serialization/deserialization of transaction data" do
    check all(
            code <- StreamData.binary(),
            content <- StreamData.binary(),
            secret <- StreamData.binary(),
            authorized_key_seeds <- StreamData.list_of(StreamData.binary(length: 32)),
            transfers <-
              StreamData.map_of(StreamData.binary(length: 32), StreamData.float(min: 0.0)),
            recipients <- list_of(StreamData.binary(length: 32))
          ) do
      authorized_public_keys =
        Enum.map(authorized_key_seeds, fn seed ->
          {pub, _} = Crypto.generate_deterministic_keypair(seed)
          pub
        end)

      recipients_addresses = Enum.map(recipients, &(<<0::8>> <> &1))

      transfers =
        Enum.map(transfers, fn {to, amount} ->
          %Transfer{to: <<0::8>> <> to, amount: amount}
        end)

      {tx_data, _} =
        %TransactionData{
          code: code,
          content: content,
          keys: Keys.new(authorized_public_keys, :crypto.strong_rand_bytes(32), secret),
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
      assert tx_data.keys.secret == secret
      assert Enum.all?(Map.keys(tx_data.keys.authorized_keys), &(&1 in authorized_public_keys))
      assert tx_data.recipients == recipients_addresses
      assert tx_data.ledger.uco.transfers == transfers
    end
  end
end
