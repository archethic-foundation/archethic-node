defmodule ArchEthic.Utils.Regression.Benchmark.TPS2 do
  @moduledoc """
  Spawns process and generates two seeds , allocates funds to A.
  prepare txn. During a benchmark when a msg is recived by a process
  deploy those process executes the prepared txn.
  """

  alias ArchEthic.Utils.Regression.Benchmark
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper

  @behaviour Benchmark

  def plan([_host | _nodes], _opts) do
    # port = Application.get_env(:archethic, ArchEthicWeb.Endpoint)[:http][:port]

    scenario = %{
      "Txn_processes" => fn {pid_list} ->
        benchmark(pid_list)
      end
    }

    inputs = %{
      "1-transactions" => {Enum.to_list(1)},
      "10-transactions" => {Enum.to_list(1..10)}
      # "100-transactions" => {Enum.to_list(1..100)}
    }

    {scenario,
     [
       before_each: fn {nb_txn} -> before_each_benchmark_input({nb_txn}) end,
       print: [benchmarking: true],
       inputs: inputs
     ]}
  end

  def before_each_benchmark_input({nb_transaction}) do
    pid_list =
      Enum.each(nb_transaction, fn _x ->
        spawn(ArchEthic.Utils.Regression.Benchmark.TPS2, :txn_process, [])
      end)

    {pid_list}
  end

  def benchmark(pid_list) do
    Task.async_stream(pid_list, fn pid ->
      benchmark_process(pid)
    end)
  end

  def benchmark_process(pid) do
    spawn(fn ->
      send(pid, {:deploy, self()})

      receive do
        message ->
          case message do
            {:ok, _from} -> :ok
            {:error, _from} -> :error
          end
      end
    end)
  end

  def txn_process() do
    # sender , receiver
    {sender_seed, receiver_seed} = {TPSHelper.random_seed(), TPSHelper.random_seed()}

    sender_seed
    |> TPSHelper.get_genesis_address()
    |> TPSHelper.allocate_funds()

    recipient_address =
      receiver_seed
      |> TPSHelper.get_genesis_address()

    txn =
      sender_seed
      |> TPSHelper.get_transaction(recipient_address)

    receive do
      message ->
        case message do
          {:deploy, from} ->
            case TPSHelper.deploy_txn(txn) do
              {:ok} -> send(from, {:ok, self()})
              {:error} -> send(from, {:error, self()})
            end
        end
    end
  end
end
