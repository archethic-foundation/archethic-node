defmodule Archethic.TransactionChain.TransactionDataTest do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Contract
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
              code <- StreamData.binary(),
              contract <- gen_contract(),
              content <- StreamData.binary(),
              secret <- StreamData.binary(min_length: 1),
              authorized_public_keys <-
                StreamData.list_of(gen_authorized_public_key(), min_length: 1),
              transfers <- StreamData.list_of(uco_transfer_gen()),
              recipients_list <- StreamData.list_of(recipient_gen_list()),
              recipients_map <- StreamData.list_of(recipient_gen_map())
            ) do
        tx_data_v3 = %TransactionData{
          code: code,
          content: content,
          ownerships: [
            Ownership.new(secret, :crypto.strong_rand_bytes(32), authorized_public_keys)
          ],
          ledger: %Ledger{uco: %UCOLedger{transfers: transfers}},
          recipients: recipients_list
        }

        assert {tx_data_v3, <<>>} ==
                 tx_data_v3
                 |> TransactionData.serialize(3)
                 |> TransactionData.deserialize(3)

        tx_data_v4 = %TransactionData{
          contract: contract,
          content: content,
          ownerships: [
            Ownership.new(secret, :crypto.strong_rand_bytes(32), authorized_public_keys)
          ],
          ledger: %Ledger{uco: %UCOLedger{transfers: transfers}},
          recipients: recipients_map
        }

        version = current_transaction_version()

        assert {tx_data_v4, <<>>} ==
                 tx_data_v4
                 |> TransactionData.serialize(version)
                 |> TransactionData.deserialize(version)
      end
    end
  end

  defp gen_contract() do
    gen all(
          bytecode <- StreamData.binary(min_length: 1, max_length: 2_000),
          functions <- StreamData.list_of(gen_contract_manifest_function(), max_length: 5),
          state <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([StreamData.constant("u32"), StreamData.constant("string")]),
              max_length: 5
            )
        ) do
      %Contract{
        bytecode: bytecode,
        manifest: %{
          "abi" => %{
            "state" => state,
            "functions" => Enum.into(functions, %{})
          }
        }
      }
    end
  end

  defp gen_contract_manifest_function() do
    gen all(
          name <- StreamData.string(:alphanumeric),
          input <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([StreamData.constant("u32"), StreamData.constant("string")]),
              max_length: 3
            ),
          output <-
            StreamData.map_of(
              StreamData.string(:alphanumeric),
              StreamData.one_of([StreamData.constant("u32"), StreamData.constant("string")]),
              length: 1
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

  defp recipient_gen_map() do
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
              ]),
              max_length: 3
            )
        ) do
      %Recipient{address: <<0::8, 0::8, address::binary>>, action: action, args: args}
    end
  end

  defp recipient_gen_list() do
    gen all(
          address <- StreamData.binary(length: 32),
          action <- StreamData.string(:alphanumeric, min_length: 1),
          args <-
            StreamData.list_of(
              StreamData.one_of([
                StreamData.integer(),
                StreamData.string(:alphanumeric),
                StreamData.boolean(),
                StreamData.constant(nil)
              ])
            )
        ) do
      %Recipient{address: <<0::8, 0::8, address::binary>>, action: action, args: args}
    end
  end
end
