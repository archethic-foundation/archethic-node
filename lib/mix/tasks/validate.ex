defmodule Mix.Tasks.Archethic.Proposal.Validator do
  @shortdoc "Run regression utilities to benchmark and validate nodes containing code proposal"

  @moduledoc """
    The Archethic Code Proposal Validator mix task wrapper

    ## Command line options

    * `--help` - show this help
    * `--phase=1` - launch phase 1
    * `--phase=2` - launch phase 2

  ## Example

  ```sh
  mix archethic.validate localhost
  ```

  """
  use Mix.Task

  alias Archethic.Governance.Code.Proposal.Validator

  @impl Mix.Task
  @spec run([binary]) :: any
  def run(args) do
    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             phase: :integer
           ]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, nodes} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          :ok = maybe(parsed, :phase, &Validator.run/2, [nodes, parsed[:phase]])
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
