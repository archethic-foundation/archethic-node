defmodule ArchEthic.Utils.Regression.Benchmark.EndToEndValidation do
  @moduledoc false

  require Logger

  alias ArchEthic.Crypto

  alias ArchEthic.Utils.Regression.Benchmark.SeedHolder
  alias ArchEthic.Utils.Regression.Playbook
  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.WebSocket.Client, as: WSClient

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]

    WSClient.start_link(host: host, port: port)
    Logger.info("Starting Benchmark: Transactions Per Seconds at host #{host} and port #{port}")

    seeds =
      Enum.map(0..100, fn _ ->
        :crypto.strong_rand_bytes(32)
      end)

    {:ok, pid} = SeedHolder.start_link(seeds: seeds)

    allocate_funds(SeedHolder.get_seeds(pid), host, port)

    {
      %{
        "UCO Transfer single recipient" => fn ->
          recipient_seed = Enum.random(seeds)
          uco_transfer_single_recipient(pid, host, port, recipient_seed)
        end
      },
      []
    }
  end

  defp allocate_funds(seeds, host, port, amount \\ 100) do
    recipient_addresses =
      Enum.map(
        seeds,
        fn seed ->
          seed
          |> Crypto.derive_keypair(0)
          |> elem(0)
          |> Crypto.derive_address()
        end
      )

    Playbook.batch_send_funds_to(recipient_addresses, host, port, amount)
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

  defp uco_transfer_single_recipient(pid, host, port, recipient_seed) do
    {sender_seed, index} = SeedHolder.pop_seed(pid)

    Playbook.send_transaction_with_await_replication(
      sender_seed,
      :transfer,
      get_txn_data(recipient_seed),
      host,
      port
    )

    SeedHolder.put_seed(pid, sender_seed, index)
  end
end
