defmodule Mix.Tasks.Uniris.Testnet do
  @shortdoc "Creates and runs several nodes in testnet"
  @subnet "172.16.16.0/24"
  @image "uniris-testnet"
  @output "testnet"
  @persist false
  @detach false
  @run true

  @moduledoc """
  This task generates `docker-compose.json` and optionally runs sevaral nodes in testnet.

  ## Command line options

    * `-h`, `--help` - show this help
    * `-o`, `--output` - use output folder for testnet, default "#{@output}"
    * `-s`, `--subnet` - use subnet for the network, default "#{@subnet}"
    * `-p`, `--persist` - mount data{n} to /opt/data, default "#{@persist}"
    * `-i`, `--image` - use image name for built container, default "#{@image}"
    * `-d`, `--detach` - run testnet in background, default "#{@detach}"
    * `--run/--no-run` - atuomatically run `docker-compose up`, default "#{@run}"

  ## Command line arguments
    * `seeds` - list of seeds

  ## Example

  ```sh
  mix uniris.testnet $(seq -f "seed%g" -s " " 5)
  ```

  """

  use Mix.Task

  alias Uniris.Testnet

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             output: :string,
             persist: :boolean,
             detach: :boolean,
             subnet: :string,
             image: :string,
             run: :boolean
           ],
           aliases: [
             h: :help,
             o: :output,
             p: :persist,
             d: :detach,
             s: :subnet,
             i: :image
           ]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, seeds} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          run(seeds, parsed)
        end
    end
  end

  defp run(seeds, opts) do
    dir = opts |> Keyword.get(:output, @output) |> Path.expand()
    detach = if Keyword.get(opts, :detach, @detach), do: "-d", else: ""

    File.dir?(dir) && raise ArgumentError, message: "#{dir} exists"

    opts =
      opts
      |> Keyword.put(:src, File.cwd!())
      |> Keyword.put_new(:image, @image)
      |> Keyword.put_new(:persist, @persist)
      |> Keyword.put_new(:subnet, @subnet)

    Mix.shell().info("Generating `#{dir}` for #{length(seeds)} nodes")

    :ok = seeds |> Testnet.from(opts) |> Testnet.create!(dir)

    if Keyword.get(opts, :run, @run) do
      Mix.shell().cmd("docker-compose -f #{dir}/docker-compose.json up #{detach}")
    end
  end
end
