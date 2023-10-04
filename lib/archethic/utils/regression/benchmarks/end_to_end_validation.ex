defmodule Archethic.Utils.Regression.Benchmark.EndToEndValidation do
  @moduledoc false

  require Logger

  alias Archethic.Crypto

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Benchmark.SeedHolder
  alias Archethic.Utils.Regression.Benchmark
  alias Archethic.Utils.WebSocket.Client, as: WSClient

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  @behaviour Benchmark
  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]

    endpoint = %Api{host: host, port: port, protocol: :http}

    WSClient.start_link(host: host, port: port)
    Logger.info("Starting Benchmark: Transactions Per Seconds at host #{host} and port #{port}")

    seeds =
      Enum.map(0..100, fn _ ->
        :crypto.strong_rand_bytes(32)
      end)

    {:ok, pid} = SeedHolder.start_link(seeds: seeds)

    amount = 100

    Api.send_funds_to_seeds(
      SeedHolder.get_seeds(pid)
      |> Enum.map(fn seed -> {seed, amount} end)
      |> Enum.into(%{}),
      endpoint
    )

    {
      %{
        "UCO Transfer single recipient" => fn ->
          recipient_seed = SeedHolder.get_random_seed(pid)
          uco_transfer_single_recipient(pid, recipient_seed, endpoint)
        end
      },
      [parallel: 4]
    }
  end

  defp get_txn_data(receiver_seed) do
    recipient_address =
      receiver_seed
      |> Crypto.derive_keypair(0)
      |> elem(0)
      |> Crypto.derive_address()

    %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 10
            }
          ]
        }
      }
    }
  end

  defp uco_transfer_single_recipient(pid, recipient_seed, endpoint) do
    {sender_seed, index} = SeedHolder.pop_seed(pid)

    Api.send_transaction_with_await_replication(
      sender_seed,
      :transfer,
      get_txn_data(recipient_seed),
      endpoint
    )

    SeedHolder.put_seed(pid, sender_seed, index)
  end
end
