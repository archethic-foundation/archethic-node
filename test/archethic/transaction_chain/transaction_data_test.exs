defmodule Archethic.TransactionChain.TransactionDataTest do
  @moduledoc false

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.Recipient

  use ArchethicCase
  import ArchethicCase

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
  end
end
