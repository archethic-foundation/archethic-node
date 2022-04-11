defmodule ArchEthic.Utils.Regression.Benchmark.NodeThroughput do
  @moduledoc """
  Using Publically exposed Api To Benchmark
  """

  # alias modules

  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper
  alias ArchEthic.Utils.Regression.Benchmark
  # behaviour
  @behaviour Benchmark

  def plan([host | _nodes], _opts) do
    IO.inspect(host, label: "host var")
    IO.inspect(binding())

    scenario = %{
      "One to One Random wallet Transfers" => fn {pid_list, host, port} ->
        benchmark(pid_list, host, port)
      end
    }

    inputs = %{
      "Input: 1 Txns" => [1]
      # "Input: 2 Txns" => [1, 2]
      # "Input: 3 Txns" => Enum.to_list(1..3),
      # "Input: 4 Txns" => Enum.to_list(1..4)
      # "Input: 10 Txns" => Enum.to_list(1..10),
      # "Input: 100 Txns" => Enum.to_list(1..100),
      # "Input: 1000 Txns" => Enum.to_list(1..1000)
    }

    opts = [
      before_each: fn {nb_txn, host, port} ->
        before_each_benchmark_input({nb_txn, host, port})
      end,
      print: [benchmarking: true],
      inputs: inputs,
      formatters: [
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    ]

    {scenario, opts}
  end

  def before_each_benchmark_input({nb_transaction, host, port}) do
    pid_list =
      Enum.map(nb_transaction, fn _x ->
        spawn(ArchEthic.Utils.Regression.Benchmarks.NodeTPS, :txn_process, [host, port])
      end)

    {pid_list, host, port}
  end

  def benchmark(pid_list, _host, _port) do
    Enum.each(pid_list, fn pid ->
      spawn(ArchEthic.Utils.Regression.Benchmarks.NodeTPS, :benchmark_process, [pid])
    end)
  end

  def benchmark_process(pid) do
    spawn(fn ->
      _a = send(pid, {:deploy, self()})

      receive do
        message ->
          case message do
            {:ok, _from} -> :ok
            {:error, _from} -> :error
          end
      end
    end)
  end

  def txn_process(host, port) do
    # sender , receiver
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
      |> TPSHelper.build_txn(recipient_address, recipient_address, :transfer, host, port)

    receive do
      message ->
        case message do
          {:deploy, from} ->
            case TPSHelper.deploy_txn(txn, host, port) do
              {:ok} -> _a = send(from, {:ok, self()})
              {:error} -> _a = send(from, {:error, self()})
            end
        end
    end
  end
end
