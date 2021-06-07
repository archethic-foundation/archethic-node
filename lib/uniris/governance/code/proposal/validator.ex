defmodule Uniris.Governance.Code.Proposal.Validator do
  @moduledoc """
  The Uniris Code Proposal Validator task is to validate Uniris Code Proposal.
  It is designed to run supervised by an os process with witch it communicates
  trough stdin/stdout.
  """
  require Logger

  alias Uniris.Benchmark.Balance
  alias Uniris.Playbook.UCO
  alias Uniris.Utils
  alias Uniris.WebClient

  @playbooks [UCO]
  @benchmarks [Balance]

  @marker Application.compile_env(:uniris, :marker)

  def main(args) do
    IO.puts("Validating #{inspect(args)}")

    # fake elixir path for benchee when running as escript
    :ets.insert_new(
      :code_names,
      {'elixir', '/usr/local/lib/elixir/bin/../lib/elixir', 'elixir', []}
    )

    validate(args,
      before: true,
      after: true,
      upgrade: true,
      validate: true,
      benchmarks: @benchmarks,
      playbooks: @playbooks
    )
  end

  def validate(nodes, opts \\ []) do
    start = System.monotonic_time(:second)

    opts =
      opts
      |> Keyword.put_new(:playbooks, @playbooks)
      |> Keyword.put_new(:benchmarks, @benchmarks)

    with true <- testnet_up?(nodes),
         :ok <- maybe(opts, :before, &run_benchmarks/2, [nodes, [{:phase, :before} | opts]]),
         :ok <- maybe(opts, :upgrade, &await_upgrade/1, [nodes]),
         :ok <- maybe(opts, :after, &run_benchmarks/2, [nodes, [{:phase, :after} | opts]]),
         :ok <- maybe(opts, :validate, &run_playbooks/2, [nodes, opts]),
         {:ok, metrics} <-
           get_metrics("collector", 9090, 5 + System.monotonic_time(:second) - start) do
      File.write!(Utils.mut_dir("metrics"), :erlang.term_to_iovec(metrics))
    end
  end

  defp maybe(opts, key, func, args) do
    if opts[key] do
      apply(func, args)
    else
      :ok
    end
  end

  @node_up_timeout 5 * 60 * 1000

  defp testnet_up?(nodes) do
    Logger.debug("Ensure #{inspect(nodes)} are up and ready")

    nodes
    |> Task.async_stream(&node_up?/1, ordered: false, timeout: @node_up_timeout)
    |> Enum.into([])
    |> Enum.all?(&(&1 == {:ok, :ok}))
  end

  defp node_up?(node, start \\ System.monotonic_time(:millisecond), timeout \\ 5 * 60_000)

  defp node_up?(node, start, timeout) do
    port = Application.get_env(:uniris, UnirisWeb.Endpoint)[:http][:port]

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

  defp await_upgrade(args) do
    IO.puts("#{@marker} | #{inspect(args)}")
    Port.open({:fd, 0, 1}, [:out, {:line, 256}]) |> Port.command("")
    IO.gets("Continue? ") |> IO.puts()
  end

  defp run_playbooks(nodes, opts) do
    Logger.debug("Running playbooks on #{inspect(nodes)} with #{inspect(opts)}")
    (opts[:playbooks] || []) |> Enum.each(fn playbook -> playbook.play!(nodes, opts) end)
  end

  defp run_benchmarks(nodes, opts) do
    Logger.debug("Running benchmarks on #{inspect(nodes)} with #{inspect(opts)}")
    tag = Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

    run_benchmark = fn benchmark ->
      Logger.info("Running benchmark #{benchmark}")
      save = Utils.mut_dir("#{benchmark}.benchee")
      save_opts = [title: benchmark, save: [path: save, tag: tag], load: save]
      {bench_plan, bench_opts} = benchmark.plan(nodes, opts)
      Benchee.run(bench_plan, Keyword.merge(save_opts, bench_opts))
    end

    (opts[:benchmarks] || []) |> Enum.each(run_benchmark)
  end

  defp get_metrics(host, port, range) do
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
end
