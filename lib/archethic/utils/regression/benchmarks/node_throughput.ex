defmodule ArchEthic.Utils.Regression.Benchmark.NodeThroughput do
  @moduledoc """
  Using Publically exposed Api To Benchmark
  """
  require Logger

  # alias modules

  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper
  alias ArchEthic.Utils.Regression.Benchmark

  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  # behaviour
  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]

    {:ok, _pid} = ArchEthic.Utils.GraphQL.GraphqlClient.supervisor()
    Logger.info("Starting Benchmark: Transactions Per Seconds at host #{host} and port #{port}")

    scenario = %{
      "One to One Random wallet Transfers" => fn -> benchmark(host, port) end
    }

    opts = [
      print: [benchmarking: true],
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ],
      parallel: 1
    ]

    {scenario, opts}
  end

  def benchmark(host, port) do
    via_helpers(host, port)
    # via_playbook(host, port)
  end

  # gives error via playbook methods,
  # erro : thrown is invalid txns
  def via_playbook(host, port) do
    alias ArchEthic.Utils.Regression.Playbook
    # IO.inspect(binding(), label: "txn_process")

    {sender_seed, receiver_seed} = {TPSHelper.random_seed(), TPSHelper.random_seed()}

    sender_seed
    |> TPSHelper.derive_keypair()
    |> TPSHelper.acquire_genesis_address()
    |> Playbook.send_funds_to(host, port)

    recipient_address =
      receiver_seed
      |> TPSHelper.derive_keypair()
      |> TPSHelper.acquire_genesis_address()

    txn_data = %TransactionData{
      ledger: %Ledger{
        uco: %UCOLedger{
          transfers: [
            %UCOTransfer{
              to: recipient_address,
              amount: 1_000_000
            }
          ]
        }
      }
    }

    Playbook.send_transaction(sender_seed, :transfer, txn_data, host, port)
  end

  def via_helpers(host, port) do
    # IO.inspect(binding(), label: "results")
    txn_list =
      Enum.map([1], fn _x ->
        txn_process(host, port)
      end)

    _results =
      Enum.map(txn_list, fn {_, _, txn} ->
        case TPSHelper.deploy_txn(txn, host, port) do
          {:ok} -> :ok
          {:error} -> :error
        end
      end)

    # IO.inspect(
    #   Enum.map(txn_list, fn {txn_address, recipient_address, _} ->
    #     TPSHelper.verify_txn_as_txn_chain(txn_address, recipient_address, host, port)
    #   end)
    # )
  end

  def txn_process(host, port) do
    {sender_seed, receiver_seed} = {TPSHelper.random_seed(), TPSHelper.random_seed()}

    sender_seed
    |> TPSHelper.derive_keypair()
    |> TPSHelper.acquire_genesis_address()
    |> TPSHelper.allocate_funds(host, port)

    recipient_address =
      receiver_seed
      |> TPSHelper.derive_keypair()
      |> TPSHelper.acquire_genesis_address()

    txn =
      sender_seed
      |> TPSHelper.build_txn(recipient_address, :transfer, host, port)

    {txn.address, recipient_address, txn}
  end
end
