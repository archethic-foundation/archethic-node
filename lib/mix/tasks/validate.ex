defmodule Mix.Tasks.Uniris.Testnet.Validate do
  @shortdoc "Validates, benchmarks testnet"
  @bench_before false
  @upgrade false
  @bench_after false
  @validate false

  @moduledoc """
  This task validates and/or benchmarks testnet.

  ## Command line options

    * `-h`, `--help` - show this help
    * `-b`, `--before` - run benchmark before upgrade, default "#{@bench_before}"
    * `-u`, `--upgrade` - pause for upgrade, default "#{@upgrade}"
    * `-a`, `--after` - run benchmark after upgrade, default "#{@bench_after}"
    * `-v`, `--validate` - run all playbooks, default "#{@validate}"

  ## Example

  ```sh
  mix uniris.testnet.validate
  ```

  """

  use Mix.Task

  alias Uniris.Governance.Code.Proposal.Validator

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             before: :boolean,
             after: :boolean,
             upgrade: :boolean,
             validate: :boolean
           ],
           aliases: [h: :help, a: :after, b: :before, u: :upgrade, v: :validate]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, nodes} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          Validator.validate(nodes, parsed)
        end
    end
  end
end
