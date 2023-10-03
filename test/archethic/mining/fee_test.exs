defmodule Archethic.Mining.FeeTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Mining.Fee

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  alias Archethic.TransactionFactory

  alias Archethic.Utils

  use ExUnitProperties

  describe "calculate/2" do
    setup do
      add_nodes(50)
      :ok
    end

    test "should return a fee less than amount to send for a single transfer" do
      amount = 100_000_000

      assert tx_fee =
               %Transaction{
                 address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
                 type: :transfer,
                 data: %TransactionData{
                   ledger: %Ledger{
                     uco: %UCOLedger{
                       transfers: [
                         %Transfer{
                           amount: amount,
                           to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                         }
                       ]
                     }
                   }
                 },
                 previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                 previous_signature: :crypto.strong_rand_bytes(32),
                 origin_signature: :crypto.strong_rand_bytes(32)
               }
               |> Fee.calculate(0.2, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert tx_fee < amount
    end

    test "should take token unique recipients into account (token creation)" do
      address1 = random_address()

      tx_distinct_recipients = %Transaction{
        address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :token,
        data: %TransactionData{
          content: """
          {
           "aeip": [2, 8, 19],
           "supply": 300000000,
           "type": "fungible",
           "name": "My token",
           "symbol": "MTK",
           "properties": {},
           "recipients": [
             {
               "to": "#{Base.encode16(address1)}",
               "amount": 100000000
             },
             {
               "to": "#{Base.encode16(address1)}",
               "amount": 100000000
             },
             {
               "to": "#{Base.encode16(random_address())}",
               "amount": 100000000
             },
             {
               "to": "#{Base.encode16(random_address())}",
               "amount": 100000000
             }
           ]
          }
          """,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  amount: 100_000_000,
                  to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                }
              ]
            }
          }
        },
        previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        previous_signature: :crypto.strong_rand_bytes(32),
        origin_signature: :crypto.strong_rand_bytes(32)
      }

      fee_tx_distinct_recipients =
        Fee.calculate(
          tx_distinct_recipients,
          2.0,
          DateTime.utc_now(),
          ArchethicCase.current_protocol_version()
        )

      tx_uniq_recipients = %Transaction{
        address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :token,
        data: %TransactionData{
          content: """
          {
           "aeip": [2, 8, 19],
           "supply": 300000000,
           "type": "fungible",
           "name": "My token",
           "symbol": "MTK",
           "properties": {},
           "recipients": [
             {
               "to": "#{Base.encode16(address1)}",
               "amount": 100000000
             },
             {
               "to": "#{Base.encode16(random_address())}",
               "amount": 100000000
             },
             {
              "to": "#{Base.encode16(random_address())}",
              "amount": 100000000
            }
           ]
          }
          """,
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{
                  amount: 100_000_000,
                  to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                }
              ]
            }
          }
        },
        previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        previous_signature: :crypto.strong_rand_bytes(32),
        origin_signature: :crypto.strong_rand_bytes(32)
      }

      fee_tx_uniq_recipients =
        Fee.calculate(
          tx_uniq_recipients,
          2.0,
          DateTime.utc_now(),
          ArchethicCase.current_protocol_version()
        )

      tx_uniq_recipients_size =
        tx_uniq_recipients.data
        |> TransactionData.serialize(tx_uniq_recipients.version)
        |> byte_size()

      tx_distinct_recipients_size =
        tx_distinct_recipients.data
        |> TransactionData.serialize(tx_distinct_recipients.version)
        |> byte_size()

      nb_storage_nodes = 50

      diff_bytes = tx_distinct_recipients_size - tx_uniq_recipients_size
      price_per_byte = 1.0e-8 / 2.0
      price_per_storage_node = price_per_byte * diff_bytes
      diff_fee = price_per_storage_node * nb_storage_nodes

      assert fee_tx_distinct_recipients - fee_tx_uniq_recipients == diff_fee * 100_000_000
    end

    test "should take token unique recipients into account (token resupply)" do
      addr1 = random_address()

      tx_uniq_recipients = %Transaction{
        address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :token,
        data: %TransactionData{
          content: """
          {
           "aeip": [8, 18],
           "supply": 1000,
           "token_reference": "0000C13373C96538B468CCDAB8F95FDC3744EBFA2CD36A81C3791B2A205705D9C3A2",
           "recipients": [
             {
               "to": "#{Base.encode16(addr1)}",
               "amount": 100000000
             }
           ]
          }
          """
        },
        previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        previous_signature: :crypto.strong_rand_bytes(32),
        origin_signature: :crypto.strong_rand_bytes(32)
      }

      fee_tx_uniq_recipients =
        Fee.calculate(
          tx_uniq_recipients,
          2.0,
          DateTime.utc_now(),
          ArchethicCase.current_protocol_version()
        )

      addr1 = random_address()

      tx_distinct_recipients = %Transaction{
        address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :token,
        data: %TransactionData{
          content: """
          {
           "aeip": [8, 18],
           "supply": 1000,
           "token_reference": "0000C13373C96538B468CCDAB8F95FDC3744EBFA2CD36A81C3791B2A205705D9C3A2",
           "recipients": [
             {
               "to": "#{Base.encode16(addr1)}",
               "amount": 100000000
             },
             {
               "to": "#{Base.encode16(addr1)}",
               "amount": 100000000
             }
           ]
          }
          """
        },
        previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        previous_signature: :crypto.strong_rand_bytes(32),
        origin_signature: :crypto.strong_rand_bytes(32)
      }

      fee_tx_distinct_recipients =
        Fee.calculate(
          tx_distinct_recipients,
          2.0,
          DateTime.utc_now(),
          ArchethicCase.current_protocol_version()
        )

      tx_uniq_recipients_size =
        tx_uniq_recipients.data
        |> TransactionData.serialize(tx_uniq_recipients.version)
        |> byte_size()

      tx_distinct_recipients_size =
        tx_distinct_recipients.data
        |> TransactionData.serialize(tx_distinct_recipients.version)
        |> byte_size()

      nb_storage_nodes = 50

      diff_bytes = tx_distinct_recipients_size - tx_uniq_recipients_size
      price_per_byte = 1.0e-8 / 2.0
      price_per_storage_node = price_per_byte * diff_bytes
      diff_fee = price_per_storage_node * nb_storage_nodes

      assert fee_tx_distinct_recipients - fee_tx_uniq_recipients == diff_fee * 100_000_000
    end

    test "should pay additional fee for tokens without recipient" do
      tx = %Transaction{
        address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
        type: :token,
        data: %TransactionData{
          content: """
          {
           "aeip": [2, 8, 19],
           "supply": 300000000,
           "type": "fungible",
           "name": "My token",
           "symbol": "MTK",
           "properties": {}
          }
          """
        },
        previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
        previous_signature: :crypto.strong_rand_bytes(32),
        origin_signature: :crypto.strong_rand_bytes(32)
      }

      fee = Fee.calculate(tx, 2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      nb_bytes =
        tx.data
        |> TransactionData.serialize(tx.version)
        |> byte_size()

      nb_storage_nodes = 50
      price_per_byte = 1.0e-8 / 2.0
      price_per_storage_node = price_per_byte * nb_bytes
      storage_cost = price_per_storage_node * nb_storage_nodes

      min_fee = 0.01 / 2.0
      additional_fee = min_fee

      assert Utils.to_bigint(min_fee + storage_cost + additional_fee) == fee
    end

    test "should decrease the fee when the amount stays the same but the price of UCO increases" do
      fee1 =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{
                    amount: 100_000_000,
                    to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                  }
                ]
              }
            }
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      fee2 =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{
                    amount: 100_000_000,
                    to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                  }
                ]
              }
            }
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(10.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert fee2 < fee1
    end

    test "should increase the fee when the transaction size increases" do
      fee_tx_small =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            content: :crypto.strong_rand_bytes(1_000)
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(0.2, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      fee_tx_big =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            content: :crypto.strong_rand_bytes(10 * 1_000_000)
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(0.2, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert fee_tx_big > fee_tx_small
    end

    test "should consider state size" do
      tx = TransactionFactory.create_valid_transaction([])

      fee_without_state =
        Fee.calculate(tx, 0.2, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      state_utxo = %UnspentOutput{
        type: :state,
        encoded_payload: :crypto.strong_rand_bytes(1000)
      }

      fee_with_state =
        Fee.calculate(
          tx,
          0.2,
          DateTime.utc_now(),
          ArchethicCase.current_protocol_version(),
          state_utxo
        )

      assert fee_with_state > fee_without_state
    end

    test "should cost more with more replication nodes" do
      tx_fee_50_nodes =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{
                    amount: 100_000_000,
                    to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                  }
                ]
              }
            }
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      add_nodes(100)

      tx_fee_100_nodes =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{
                    amount: 100_000_000,
                    to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                  }
                ]
              }
            }
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert tx_fee_50_nodes < tx_fee_100_nodes
    end

    test "should cost more sending multiple transfers than sending a single big transfer" do
      single_tx_fee =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{
                    amount: 100_000_000_000,
                    to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                  }
                ]
              }
            }
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(0.2, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      batched_tx_fee =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :transfer,
          data: %TransactionData{
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers:
                  Enum.map(1..1000, fn _ ->
                    %Transfer{
                      amount: 100_000_000,
                      to: <<0::8, :crypto.strong_rand_bytes(32)::binary>>
                    }
                  end)
              }
            }
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(0.2, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert batched_tx_fee > single_tx_fee
    end

    test "should cost more when a token is created with multiple UTXO to create (collection)" do
      fee1 =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :token,
          data: %TransactionData{
            content:
              Jason.encode!(%{
                type: "non-fungible",
                collection: [
                  %{image: "link"},
                  %{image: "link"},
                  %{image: "link"}
                ]
              })
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      fee2 =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :token,
          data: %TransactionData{
            content:
              Jason.encode!(%{
                type: "non-fungible",
                collection: [
                  %{image: "link"},
                  %{image: "link"},
                  %{image: "link"},
                  %{image: "link"},
                  %{image: "link"},
                  %{image: "link"}
                ]
              })
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert fee2 > fee1
    end

    test "should cost more when a token is created with recipients" do
      fee1 =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :token,
          data: %TransactionData{
            content:
              Jason.encode!(%{
                type: "fungible"
              })
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      fee2 =
        %Transaction{
          address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
          type: :token,
          data: %TransactionData{
            content:
              Jason.encode!(%{
                type: "fungible",
                recipients: [
                  %{to: "", amount: 1},
                  %{to: "", amount: 1},
                  %{to: "", amount: 1}
                ]
              })
          },
          previous_public_key: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
          previous_signature: :crypto.strong_rand_bytes(32),
          origin_signature: :crypto.strong_rand_bytes(32)
        }
        |> Fee.calculate(2.0, DateTime.utc_now(), ArchethicCase.current_protocol_version())

      assert fee2 > fee1
    end

    property "should cost more with multiple recipients but being more efficient than multiple transactions" do
      check all(nb_recipients <- StreamData.integer(2..255)) do
        batch_tx =
          TransactionFactory.create_valid_transaction([],
            type: :transfer,
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers:
                  Enum.map(1..nb_recipients, fn _ ->
                    %Transfer{
                      to: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                      amount: 100_000_000
                    }
                  end)
              }
            }
          )

        batch_tx_fee =
          Fee.calculate(
            batch_tx,
            2.0,
            DateTime.utc_now(),
            ArchethicCase.current_protocol_version()
          )

        single_tx =
          TransactionFactory.create_valid_transaction([],
            type: :transfer,
            ledger: %Ledger{
              uco: %UCOLedger{
                transfers: [
                  %Transfer{
                    to: <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>,
                    amount: 100_000_000
                  }
                ]
              }
            }
          )

        single_tx_fee =
          Fee.calculate(
            single_tx,
            2.0,
            DateTime.utc_now(),
            ArchethicCase.current_protocol_version()
          )

        assert batch_tx_fee < single_tx_fee * nb_recipients
      end
    end
  end

  defp add_nodes(n) do
    Enum.each(1..n, fn i ->
      public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: i,
        first_public_key: public_key,
        last_public_key: public_key,
        geo_patch: "AAA",
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        available?: true
      })
    end)
  end
end
