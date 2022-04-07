defmodule ArchEthic.Utils.Regression.Benchmarks.NodeTPS do
  @moduledoc """
  Returns Scenario for benchamrking TPS.
  One to One Random wallet Transfers
  """
  # required
  alias ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper

  def tps() do
    {scenario, opts} = node_tps()

    Benchee.run(scenario, opts)
  end

  def node_tps() do
    scenario = %{
      "One to One Random wallet Transfers" => fn {pid_list} ->
        benchmark(pid_list)
      end
    }

    inputs = %{
      "Input: 3 Txns" => Enum.to_list(1..3),
      "Input: 5 Txns" => Enum.to_list(1..5),
      "Input: 10 Txns" => Enum.to_list(1..10),
      "Input: 100 Txns" => Enum.to_list(1..100),
      "Input: 1000 Txns" => Enum.to_list(1..1000)
    }

    opts = [
      before_each: fn nb_txn -> before_each_benchmark_input({nb_txn}) end,
      print: [benchmarking: true],
      inputs: inputs,
      formatters: [
        Benchee.Formatters.HTML,
        {Benchee.Formatters.Console, extended_statistics: true}
      ]
    ]

    {scenario, opts}
  end

  def before_each_benchmark_input({nb_transaction}) do
    pid_list =
      Enum.map(nb_transaction, fn _x ->
        spawn(ArchEthic.Utils.Regression.Benchmarks.NodeTPS, :txn_process, [])
      end)

    {pid_list}
  end

  def benchmark(pid_list) do
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

  def txn_process() do
    # sender , receiver
    {sender_seed, receiver_seed} = {TPSHelper.random_seed(), TPSHelper.random_seed()}

    sender_seed
    |> TPSHelper.derive_keys()
    |> TPSHelper.acquire_genesis_address()
    |> TPSHelper.allocate_funds()

    recipient_address =
      receiver_seed
      |> TPSHelper.derive_keys()
      |> TPSHelper.acquire_genesis_address()

    txn =
      sender_seed
      |> TPSHelper.transfer(recipient_address)

    receive do
      message ->
        case message do
          {:deploy, from} ->
            case TPSHelper.deploy_txn(txn) do
              {:ok} -> _a = send(from, {:ok, self()})
              {:error} -> _a = send(from, {:error, self()})
            end
        end
    end
  end
end
