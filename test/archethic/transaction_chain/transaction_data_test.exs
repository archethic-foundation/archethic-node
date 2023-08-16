defmodule Archethic.TransactionChain.TransactionDataTest do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.Recipient

  use ExUnitProperties
  use ArchethicCase
  import ArchethicCase

  doctest TransactionData

  describe "serialize/deserialize" do
    test "should work" do
      data = %TransactionData{
        code: "@version 1\ncondition inherit: []",
        content: "Lorem ipsum dolor sit amet, consectetur adipiscing eli",
        ownerships: [
          %Ownership{
            secret: :crypto.strong_rand_bytes(24),
            authorized_keys: %{}
          }
        ],
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: [
              %UCOLedger.Transfer{
                amount: 1_000,
                to: random_address()
              },
              %UCOLedger.Transfer{
                amount: 1_000_000,
                to: random_address()
              }
            ]
          },
          token: %TokenLedger{
            transfers: [
              %TokenLedger.Transfer{
                token_address: random_address(),
                amount: 1_000,
                to: random_address()
              },
              %TokenLedger.Transfer{
                token_address: random_address(),
                token_id: 1,
                amount: 1_000_000,
                to: random_address()
              }
            ]
          }
        },
        recipients: [
          random_address(),
          random_address(),
          %Recipient{
            address: random_address(),
            action: "pet",
            args: ["Flak", "Fidji", "Max"]
          }
        ]
      }

      assert {^data, <<>>} =
               data
               |> TransactionData.serialize(1)
               |> TransactionData.deserialize(1)
    end

    property "symmetric serialization/deserialization of transaction data" do
      check all(
              code <- StreamData.binary(),
              content <- StreamData.binary(),
              secret <- StreamData.binary(min_length: 1),
              authorized_key_seeds <-
                StreamData.list_of(StreamData.binary(length: 32), min_length: 1),
              transfers <-
                StreamData.map_of(StreamData.binary(length: 32), StreamData.positive_integer()),
              recipients_data <- list_of(StreamData.binary(length: 32))
            ) do
        authorized_public_keys =
          Enum.map(authorized_key_seeds, fn seed ->
            {pub, _} = Crypto.generate_deterministic_keypair(seed)
            pub
          end)

        recipients =
          Enum.map(recipients_data, fn r -> %Recipient{address: <<0::8, 0::8, r::binary>>} end)

        transfers =
          Enum.map(transfers, fn {to, amount} ->
            %UCOLedger.Transfer{to: <<0::8, 0::8, to::binary>>, amount: amount}
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
            recipients: recipients
          }
          |> TransactionData.serialize(current_transaction_version())
          |> TransactionData.deserialize(current_transaction_version())

        assert tx_data.code == code
        assert tx_data.content == content
        assert List.first(tx_data.ownerships).secret == secret

        assert Enum.all?(
                 Ownership.list_authorized_public_keys(List.first(tx_data.ownerships)),
                 &(&1 in authorized_public_keys)
               )

        assert tx_data.recipients == recipients
        assert tx_data.ledger.uco.transfers == transfers
      end
    end
  end
end
