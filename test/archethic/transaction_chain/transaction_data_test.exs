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
    test "should work tx_version 1" do
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
          %Recipient{address: random_address()},
          %Recipient{address: random_address()}
        ]
      }

      assert {^data, <<>>} =
               data
               |> TransactionData.serialize(1)
               |> TransactionData.deserialize(1)
    end

    test "should work tx_version 2" do
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
          %Recipient{address: random_address()},
          %Recipient{address: random_address()},
          %Recipient{
            address: random_address(),
            action: "pet",
            args: ["Flak", "Fidji", "Max"]
          }
        ]
      }

      assert {^data, <<>>} =
               data
               |> TransactionData.serialize(2)
               |> TransactionData.deserialize(2)
    end

    property "symmetric serialization/deserialization of transaction data" do
      check all(
              # code <- StreamData.binary(),
              contract <- gen_contract(),
              content <- StreamData.binary(),
              secret <- StreamData.binary(min_length: 1),
              authorized_public_keys <-
                StreamData.list_of(gen_authorized_public_key(), min_length: 1),
              transfers <- StreamData.list_of(uco_transfer_gen()),
              recipients <- StreamData.list_of(recipient_gen())
            ) do
        {tx_data, _} =
          %TransactionData{
            # code: code,
            contract: contract,
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

        # assert tx_data.code == code
        assert tx_data.contract == contract

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

  defp gen_contract() do
    gen all(
          bytecode <- StreamData.binary(min_length: 1),
          functions <- StreamData.list_of(gen_contract_manifest_function()),
          state <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([StreamData.constant("u32"), StreamData.constant("string")])
            )
        ) do
      %{
        bytecode: bytecode,
        manifest: Jason.encode!(%{
          "abi" => %{
            "state" => state,
            "functions" => Enum.into(functions, %{})
          }
        })
      }
    end
  end

  defp gen_contract_manifest_function() do
    gen all(
          name <- StreamData.string(:alphanumeric),
          input <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([StreamData.constant("u32"), StreamData.constant("string")])
            ),
          output <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([StreamData.constant("u32"), StreamData.constant("string")])
            ),
          type <-
            StreamData.one_of([
              StreamData.constant("action"),
              StreamData.constant("publicFunction")
            ])
        ) do
      {name,
       %{
         "type" => type,
         "input" => input,
         "output" => output
       }}
    end
  end

  defp uco_transfer_gen() do
    gen all(
          to <- StreamData.binary(length: 32),
          amount <- StreamData.positive_integer()
        ) do
      %UCOLedger.Transfer{to: <<0::8, 0::8, to::binary>>, amount: amount}
    end
  end

  defp gen_authorized_public_key() do
    StreamData.binary(length: 32)
    |> StreamData.map(fn seed ->
      {pub, _} = Crypto.generate_deterministic_keypair(seed)
      pub
    end)
  end

  defp recipient_gen() do
    gen all(
          address <- StreamData.binary(length: 32),
          action <- StreamData.string(:alphanumeric, min_length: 1),
          args <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([
                StreamData.integer(),
                StreamData.string(:alphanumeric),
                StreamData.boolean(),
                StreamData.constant(nil)
              ])
            )
          # args <-
          #   StreamData.list_of(
          #     StreamData.one_of([
          #       StreamData.integer(),
          #       StreamData.string(:alphanumeric),
          #       StreamData.boolean(),
          #       StreamData.constant(nil)
          #     ])
          #   )
        ) do
      %Recipient{address: <<0::8, 0::8, address::binary>>, action: action, args: args}
    end
  end
end
