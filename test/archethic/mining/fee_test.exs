defmodule Archethic.Mining.FeeTest do
  use ArchethicCase

  alias Archethic.Mining.Fee

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer

  describe "calculate/2 with 50 storage nodes" do
    setup do
      add_nodes(50)
      :ok
    end

    test "should return a fee less than amount to send for a single transfer" do
      # 0.05014249 UCO for 1 UCO at $0.2
      assert 5_014_249 =
               %Transaction{
                 address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
                 type: :transfer,
                 data: %TransactionData{
                   ledger: %Ledger{
                     uco: %UCOLedger{
                       transfers: [
                         %Transfer{
                           amount: trunc(100_000_000),
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
               |> Fee.calculate(0.2)
    end

    test "should increase fee when the amount increases for single transfer " do
      # 0.00501425 UCO for 1 UCO
      assert 501_425 ==
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
               |> Fee.calculate(2.0)

      # 0.00501425 UCO for 60 UCO
      assert 501_425 =
               %Transaction{
                 address: <<0::8, :crypto.strong_rand_bytes(32)::binary>>,
                 type: :transfer,
                 data: %TransactionData{
                   ledger: %Ledger{
                     uco: %UCOLedger{
                       transfers: [
                         %Transfer{
                           amount: 6_000_000_000,
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
               |> Fee.calculate(2.0)
    end

    test "should decrease the fee when the amount stays the same but the price of UCO increases" do
      # 0.00501425 UCO for 1 UCO at $ 2.0
      assert 501_425 =
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
               |> Fee.calculate(2.0)

      # 0.00100285 UCO for 1 UCO at $10.0
      assert 100_285 =
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
               |> Fee.calculate(10.0)
    end

    test "sending multiple transfers should cost more than sending a single big transfer" do
      # 0.05014249 UCO for 1_000 UCO
      assert 5_014_249 =
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
               |> Fee.calculate(0.2)

      # 500.1525425 UCO for 1000 transfer of 1 UCO
      assert 50_015_254_250 =
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
               |> Fee.calculate(0.2)
    end

    test "should increase the fee when the transaction size increases" do
      # 0.05254000 UCO to store 1KB
      assert 5_254_000 =
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
               |> Fee.calculate(0.2)

      # 25.05004 UCO to store 10MB
      assert 2_505_004_000 =
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
               |> Fee.calculate(0.2)
    end

    test "should cost more with more replication nodes" do
      # 50 nodes: 0.00501425 UCO
      assert 501_425 =
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
               |> Fee.calculate(2.0)

      add_nodes(100)

      # 150 nodes: 0.00504275 UCO
      assert 504_275 =
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
               |> Fee.calculate(2.0)
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
