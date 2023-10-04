defmodule Archethic.Utils.Regression do
  @moduledoc """
  Run some regression test to ensure the right behavior of the system
  """
  require Logger

  alias Archethic.Utils

  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias Archethic.Utils.Regression.Playbook.UCO

  alias Archethic.Utils.WebClient
  alias Archethic.Utils.Regression.Benchmark.EndToEndValidation
  alias Archethic.Utils.Regression.Benchmark.P2PMessage

  @playbooks [UCO, SmartContract]
  @benchmarks [P2PMessage, EndToEndValidation]

  def run_playbooks(nodes, opts \\ []) do
    Logger.debug("Running playbooks on #{inspect(nodes)} with #{inspect(opts)}")

    Enum.each(@playbooks, fn playbook ->
      playbook.play!(nodes, opts)
      Process.sleep(100)
    end)
  end

  def run_benchmarks(nodes, opts \\ []) do
    Logger.debug("Running benchmarks on #{inspect(nodes)} with #{inspect(opts)}")
    tag = Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

    run_benchmark = fn benchmark ->
      Logger.info("Running benchmark #{benchmark}")
      save = Utils.mut_dir("#{benchmark}.benchee")
      save_opts = [title: benchmark, save: [path: save, tag: tag], load: save]
      {bench_plan, bench_opts} = benchmark.plan(nodes, opts)
      Benchee.run(bench_plan, Keyword.merge(save_opts, bench_opts))
    end

    Enum.each(@benchmarks, run_benchmark)
  end

  def get_metrics(host, port, range) do
    Logger.debug("Collecting metrics for last #{range} seconds")

    WebClient.with_connection(host, port, fn conn ->
      with {:ok, conn, %{"status" => "success", "data" => metrics}} <-
             WebClient.json(conn, "/api/v1/label/__name__/values"),
           {:ok, conn, data} <- collect_metrics(conn, metrics, range) do
        {:ok, conn, data}
      else
        {:error, conn, error} -> {:error, conn, error}
      end
    end)
  end

  defp query_metric(metric, range, resolution \\ 5),
    do: "/api/v1/query?query=#{metric}[#{range}s:#{resolution}s]"

  defp collect_metrics(conn, metrics, range, acc \\ [])
  defp collect_metrics(conn, [], _, acc), do: {:ok, conn, acc}

  defp collect_metrics(conn, [m | metrics], range, acc) do
    case WebClient.json(conn, query_metric(m, range)) do
      {:ok, conn, %{"status" => "success", "data" => %{"result" => data}}} ->
        collect_metrics(conn, metrics, range, [data | acc])

      {:error, conn, error} ->
        {:error, conn, error}
    end
  end

  @node_up_timeout 5 * 60 * 1000

  def nodes_up?(nodes) do
    Logger.debug("Ensure #{inspect(nodes)} are up and ready")

    nodes
    |> Task.async_stream(&node_up?/1, ordered: false, timeout: @node_up_timeout)
    |> Enum.into([])
    |> Enum.all?(&(&1 == {:ok, :ok}))
  end

  def node_up?(node, start \\ System.monotonic_time(:millisecond), timeout \\ 5 * 60_000)

  def node_up?(node, start, timeout) do
    port =
      if System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet" do
        40_000
      else
        Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]
      end

    case WebClient.with_connection(node, port, &WebClient.request(&1, "GET", "/up")) do
      {:ok, ["up"]} ->
        :ok

      {:ok, _} ->
        Process.sleep(250)
        node_up?(node, start, timeout)

      {:error, _} ->
        Process.sleep(500)

        if System.monotonic_time(:millisecond) - start < timeout do
          node_up?(node, start, timeout)
        else
          {:error, :timeout}
        end
    end
  end
end
