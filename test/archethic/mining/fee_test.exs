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
      # 0.050048 UCO for 1 UCO at $0.2
      assert 50_048_000 =
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
      # 0.050048 UCO for 1 UCO
      assert 5_004_800 ==
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

      # 0.060048 UCO for 60 UCO
      assert 6_004_800 =
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
      # 0.050048 UCO for 1 UCO at $ 2.0
      assert 5_004_800 =
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

      # 0.0100096 UCO for 1 UCO at $10.0
      assert 1_000_960 =
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
      # 1.00048 UCO for 1_000 UCO
      assert 100_048_000 =
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

      # 501.1028775.UCO for 1000 transfer of 1 UCO
      assert 50_110_287_750 =
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
      # 0.5 UCO to store 1KB
      assert 50_287_750 =
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

      # 25.5 UCO to store 10MB
      assert 2_550_037_750 =
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
      # 50 nodes: 0.050048 UCO
      assert 5_004_800 =
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

      # 150 nodes: 0.050144 UCO
      assert 5_014_400 =
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
