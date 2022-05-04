defmodule Mix.Tasks.Archethic.Testnet do
  @shortdoc "Creates and runs several nodes in testnet"
  @subnet "172.16.17.0/24"
  @image "archethic-node"
  @output ".devnet"
  @detach false
  @run true

  @moduledoc """
  This task generates `docker-compose.json` and optionally runs sevaral nodes in testnet.

  ## Command line options

    * `-h`, `--help` - show this help
    * `-o`, `--output` - use output folder for testnet, default "#{@output}"
    * `-s`, `--subnet` - use subnet for the network, default "#{@subnet}"
    * `-i`, `--image` - use image name for built container, default "#{@image}"
    * `-d`, `--detach` - run testnet in background, default "#{@detach}"
    * `--run/--no-run` - atuomatically run `docker-compose up`, default "#{@run}"

  ## Command line arguments
    * `seeds` - list of seeds

  ## Example

  ```sh
  mix archethic.testnet 5
  ```

  """

  use Mix.Task

  alias Archethic.Utils.Testnet

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             output: :string,
             detach: :boolean,
             subnet: :string,
             image: :string,
             run: :boolean
           ],
           aliases: [
             h: :help,
             o: :output,
             d: :detach,
             s: :subnet,
             i: :image
           ]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, [nb_nodes]} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          run(String.to_integer(nb_nodes), parsed)
        end
    end
  end

  defp run(nb_nodes, opts) do
    dir = opts |> Keyword.get(:output, @output) |> Path.expand()
    detach = if Keyword.get(opts, :detach, @detach), do: "-d", else: ""

    opts =
      opts
      |> Keyword.put(:src, File.cwd!())
      |> Keyword.put_new(:image, @image)
      |> Keyword.put_new(:subnet, @subnet)

    Mix.shell().info("Generating `#{dir}` for #{nb_nodes} nodes")

    :ok = nb_nodes |> Testnet.from(opts) |> Testnet.create!(dir)

    if Keyword.get(opts, :run, @run) do
      Mix.shell().cmd("docker-compose -f #{dir}/docker-compose.json up #{detach}")
    end
  end
end
