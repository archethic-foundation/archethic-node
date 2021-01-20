defmodule Uniris.Governance.Code.CICD.Docker do
  @moduledoc """
  CICD service baked by docker
  """
  use Supervisor

  require Logger

  alias Uniris.JobCache
  alias Uniris.JobConductor

  alias Uniris.Governance.Code.CICD
  alias Uniris.Governance.Code.Proposal

  @behaviour CICD

  @ci_image __MODULE__.CIImage
  @conductor __MODULE__.Conductor

  @src_dir Application.compile_env(:uniris, :src_dir)

  @impl CICD
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      {JobCache, name: @ci_image, function: &build_ci_image/0},
      {JobConductor, name: @conductor, limit: 2}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @impl CICD
  def run_ci!(%Proposal{address: address, changes: changes}) do
    :ok = JobCache.get!(@ci_image)
    {:ok, 0} = JobConductor.conduct(&do_run_docker_ci/2, [address, changes], @conductor)
    :ok
  end

  @impl CICD
  def run_testnet!(prop = %Proposal{}, opts \\ []) do
    {:ok, _} = JobConductor.conduct(&do_run_docker_testnet/2, [prop, opts], @conductor)
    :ok
  end

  @impl CICD
  def clean(_address), do: :ok

  @impl CICD
  def get_log(address) when is_binary(address) do
    case System.cmd("docker", ["logs", container_name(address)], []) do
      {res, 0} -> {:ok, res}
      err -> {:error, err}
    end
  end

  defp container_name(address) when is_binary(address) do
    "uniris-prop-#{Base.encode16(address)}"
  end

  defp build_ci_image do
    cmd_options = [stderr_to_stdout: true, into: IO.stream(:stdio, :line), cd: @src_dir]
    docker = fn args -> System.cmd("docker", args, cmd_options) end
    {_, 0} = docker.(["build", "-t", "uniris-ci", "--target", "uniris-ci", "."])
    :ok
  end

  defp do_run_docker_ci(address, changes) do
    name = container_name(address)

    port =
      Port.open({:spawn_executable, System.find_executable("docker")}, [
        :binary,
        args: [
          "run",
          "--entrypoint",
          "/opt/code/scripts/proposal_ci_job.sh",
          "-i",
          "--name",
          name,
          "uniris-ci",
          name
        ]
      ])

    Port.command(port, [changes, "\n"])
    Port.close(port)
    wait_for_container(name, System.monotonic_time(:second))
  end

  defp wait_for_container(name, start_time) do
    Process.sleep(500)

    case System.cmd("docker", ["wait", name]) do
      {res, 0} ->
        res |> Integer.parse() |> elem(0)

      {err, _} ->
        Logger.warning("Docker CI: #{inspect(err)}")

        if System.monotonic_time() - start_time < 20 * 60 do
          wait_for_container(name, start_time)
        else
          1
        end
    end
  end

  defp do_run_docker_testnet(prop = %Proposal{}, opts) do
    IO.puts("Running proposal #{inspect(prop)} with #{inspect(opts)}")
  end
end
