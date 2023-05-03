defmodule Mix.Tasks.Archethic.Regression do
  @shortdoc "Run regression utilities to benchmark and validate nodes"
  @bench false
  @validate false

  @moduledoc """
  This task validates and/or benchmarks a network of nodes.

  ## Command line options

    * `--help` - show this help
    * `--bench` - run benchmark "#{@bench}"
    * `--playbook` - run all playbooks, default "#{@validate}"

  ## Example

  ```sh
  mix archethic.regression --bench localhost
  ```

  """

  use Mix.Task

  alias Archethic.Utils.Regression

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:telemetry)

    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             bench: :boolean,
             playbook: :boolean
           ]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, nodes} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          true = Regression.nodes_up?(nodes)
          :ok = maybe(parsed, :bench, &Regression.run_benchmarks/1, [nodes])
          :ok = maybe(parsed, :playbook, &Regression.run_playbooks/1, [nodes])
        end
    end
  end

  defp maybe(opts, key, func, args) do
    if opts[key] do
      apply(func, args)
    else
      :ok
    end
  end
end
