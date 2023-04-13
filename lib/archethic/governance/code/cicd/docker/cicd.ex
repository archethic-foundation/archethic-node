defmodule Archethic.Governance.Code.CICD.Docker do
  @moduledoc """
  CICD service backed by docker.

  The service relies on the `Dockerfile` with two targets: `archethic-ci` and
  `archethic-cd`.

  The `archethic-ci` target produces an image with build tools. Its goal is to
  compile the source code into `archethic_node` release. The CI part is powered by
  `scripts/proposal_ci_job.sh`. The script runs in a container named
  `archethic-prop-{address}`, it produces: release upgrade of `archethic_node`, new
  version of `archethic-proposal-validator`, and combined log of application of a
  code proposal to the source code, execution of unit tests, and log from
  linter. The log can be obtained with `docker logs`, the release upgrade and
  the validator with `docker cp`, after that the container can be disposed.

  The `archethic-cd` target produces an image capable of running `archethic_node`
  release.
  """
  use Supervisor

  require Logger

  alias Archethic.Governance.Code.CICD
  alias Archethic.Governance.Code.Proposal

  alias Archethic.Utils.JobCache
  alias Archethic.Utils.JobConductor
  alias Archethic.Utils.Testnet
  alias Archethic.Utils.Testnet.Subnet

  import Supervisor, only: [child_spec: 2]

  @behaviour CICD

  @ci_image __MODULE__.CIImage
  @cd_image __MODULE__.CDImage

  @ci_conductor __MODULE__.CIConductor
  @cd_conductor __MODULE__.CDConductor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      child_spec({JobCache, name: @ci_image, function: &build_ci_image/0}, id: @ci_image),
      child_spec({JobCache, name: @cd_image, function: &build_cd_image/0}, id: @cd_image),
      child_spec({JobConductor, name: @ci_conductor, limit: 2}, id: @ci_conductor),
      child_spec({JobConductor, name: @cd_conductor, limit: 2}, id: @cd_conductor)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @impl CICD
  def run_ci!(prop = %Proposal{changes: changes}) do
    File.write!("./proposal.diff", changes)
    run!(prop, @ci_image, @ci_conductor, &do_run_docker_ci/1, "CI failed")
    File.rm!("./proposal.diff")
  end

  @impl CICD
  def run_testnet!(prop = %Proposal{}) do
    run!(prop, @cd_image, @cd_conductor, &do_run_docker_testnet/1, "CD failed")
  end

  @impl CICD
  def clean(_address), do: :ok

  @impl CICD
  def get_log(address) when is_binary(address) do
    case System.cmd("docker", ["logs", container_name(address)]) do
      {res, 0} -> {:ok, res}
      err -> {:error, err}
    end
  end

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ [CICD] ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  @src_dir Application.compile_env(:archethic, :src_dir)

  @cmd_options [stderr_to_stdout: true, into: IO.stream(:stdio, :line), cd: @src_dir]

  defp docker(args, opts \\ @cmd_options), do: System.cmd("docker", args, opts)

  defp container_name(address) when is_binary(address) do
    "archethic-prop-#{Base.encode16(address)}"
  end

  defp run!(prop = %Proposal{address: address}, image, conductor, func, exception) do
    with :ok <- JobCache.get!(image),
         {:ok, 0} <- JobConductor.conduct(func, [prop], conductor) do
      :ok
    else
      error ->
        Logger.error("#{exception} #{inspect(error)}", address: Base.encode16(address))
        raise exception
    end
  end

  defp docker_wait(name, start_time, start_timeout \\ 10) do
    Process.sleep(250)
    # Block until one or more containers stop, then print their exit codes
    case System.cmd("docker", ["wait", name]) do
      {res, 0} ->
        res |> Integer.parse() |> elem(0)

      {err, _} ->
        Logger.warning("docker wait: #{inspect(err)}")

        # on a busy host docker may require more time to start a container
        if System.monotonic_time(:second) - start_time < start_timeout do
          docker_wait(name, start_time, start_timeout)
        else
          1
        end
    end
  end

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ [CI] ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  defp build_ci_image do
    {user_id, _} = System.cmd("id", ["-u"])
    {group_id, _} = System.cmd("id", ["-g"])

    {_, 0} =
      docker([
        "build",
        "-t",
        "archethic-ci",
        "--target",
        "archethic-ci",
        "--build-arg",
        "USER_ID=#{String.trim(user_id)}",
        "--build-arg",
        "GROUP_ID=#{String.trim(group_id)}",
        "."
      ])

    :ok
  end

  @ci_script "/opt/code/scripts/governance/proposal_ci_job.sh"

  defp do_run_docker_ci(%Proposal{address: address, changes: changes, description: description}) do
    Logger.info("Verify proposal", address: Base.encode16(address))
    name = container_name(address)

    args = [
      "run",
      "--entrypoint",
      @ci_script,
      "-i",
      "--name",
      name,
      "archethic-ci",
      name,
      description,
      address
    ]

    port = Port.open({:spawn_executable, System.find_executable("docker")}, [:binary, args: args])

    # wait 250 ms or fail sooner
    ref = Port.monitor(port)

    receive do
      {:DOWN, ^ref, :port, ^port, :normal} ->
        raise RuntimeError, message: "failed to run: docker #{Enum.join(args, " ")}"
    after
      250 -> :ok
    end

    Port.command(port, [changes, "\n"])
    Port.close(port)
    docker_wait(name, System.monotonic_time(:second))
  end

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ [CD] ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  defp build_cd_image do
    {user_id, _} = System.cmd("id", ["-u"])
    {group_id, _} = System.cmd("id", ["-g"])

    {_, 0} =
      docker([
        "build",
        "-t",
        "archethic-cd",
        "--build-arg",
        "USER_ID=#{String.trim(user_id)}",
        "--build-arg",
        "GROUP_ID=#{String.trim(group_id)}",
        "."
      ])

    :ok
  end

  @marker Application.compile_env(:archethic, :marker)
  @releases "/opt/code/_build/prod/rel/archethic_node/releases"
  @release "archethic_node.tar.gz"

  defp do_run_docker_testnet(%Proposal{address: address, version: version}) do
    address_encoded = Base.encode16(address)
    Logger.info("Running proposal", address: address_encoded)

    dir = temp_dir("utn-#{address_encoded}-")
    nb_nodes = 5

    compose_prefix =
      dir
      |> Path.basename()
      |> String.downcase()

    validator_1_container = "#{compose_prefix}-validator_1-1"
    validator_2_container = "#{compose_prefix}-validator_2-1"

    nodes = 1..nb_nodes |> Enum.map(&"#{compose_prefix}-node#{&1}-1")

    with :ok <- Logger.info("#{dir} Prepare", address: address_encoded),
         :ok <- testnet_prepare(dir, address, version),
         :ok <- Logger.info("#{dir} Start", address: address_encoded),
         %{cmd: {_, 0}, testnet: _testnet} <- testnet_start(dir, nb_nodes),
         # wait until the validator is ready for upgrade
         :ok <- Logger.info("#{dir} Part I", address: address_encoded),
         {:ok, _} <- wait_for_marker(validator_1_container, @marker),
         :ok <- Logger.info("#{dir} Upgrade", address: address_encoded),
         true <- testnet_upgrade(dir, nodes, version),
         :ok <- Logger.info("#{dir} Part II", address: address_encoded),
         {_, 0} <- validator_continue(dir),
         0 <-
           docker_wait(validator_2_container, System.monotonic_time(:second)) do
      testnet_cleanup(dir, 0, address_encoded)
    else
      _ ->
        testnet_cleanup(dir, 1, address_encoded)
    end
  end

  defp testnet_prepare(dir, address, version) do
    ci = container_name(address)

    with :ok <- File.mkdir_p!(dir),
         {_, 0} <- docker(["cp", "#{ci}:#{@releases}/#{version}/#{@release}", dir]) do
      :ok
    else
      _ -> :error
    end
  end

  @subnet "172.16.100.0/24"

  defp testnet_start(dir, nb_nodes) do
    compose = compose_file(dir)
    options = [image: "archethic-cd", dir: dir, src: @src_dir, persist: false]

    Stream.iterate(@subnet, &Subnet.next/1)
    |> Stream.take(123)
    |> Stream.map(fn subnet ->
      testnet = Testnet.from(nb_nodes, Keyword.put(options, :subnet, subnet))

      with :ok <- Testnet.create!(testnet, dir) do
        %{
          testnet: testnet,
          cmd: System.cmd("docker-compose", ["-f", compose, "up", "-d"], @cmd_options)
        }
      end
    end)
    |> Stream.filter(&(elem(&1[:cmd], 1) == 0))
    |> Enum.at(0)
  end

  defp testnet_upgrade(dir, containers, version) do
    dst = "/opt/app/releases/#{version}"
    rel = Path.join(dir, @release)

    trap_exit = Process.flag(:trap_exit, true)

    result =
      containers
      |> Task.async_stream(
        fn c ->
          with {_, 0} <- docker(["exec", c, "mkdir", "-p", "#{dst}"]),
               {_, 0} <- docker(["cp", rel, "#{c}:#{dst}/#{@release}"]),
               {_, 0} <- docker(["exec", c, "./bin/archethic_node", "upgrade", version]) do
            :ok
          else
            error ->
              Logger.error("Upgrade failed #{inspect(error)}")
              raise "Upgrade failed"
          end
        end,
        timeout: 30_000,
        ordered: false
      )
      |> Enum.into([])
      |> Enum.all?(&(elem(&1, 0) == :ok))

    Process.flag(:trap_exit, trap_exit)
    result
  end

  defp wait_for_marker(container_name, marker, timeout \\ 60_000) do
    args = ["logs", container_name, "--follow", "--tail", "10"]
    opts = [:binary, :use_stdio, :stderr_to_stdout, line: 8192, args: args]

    task =
      Task.async(fn ->
        {:spawn_executable, System.find_executable("docker")}
        |> Port.open(opts)
        |> wait_for_marker_loop(marker)
      end)

    try do
      {:ok, Task.await(task, timeout)}
    catch
      :exit, err ->
        Task.shutdown(task)
        {:error, err}
    end
  end

  defp wait_for_marker_loop(port, marker) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        Logger.debug(line)

        if String.starts_with?(line, marker) do
          line
        else
          wait_for_marker_loop(port, marker)
        end

      {^port, other} ->
        Logger.warning("Received #{inspect(other)} while reading container logs")
        wait_for_marker_loop(port, marker)
    end
  end

  defp validator_continue(dir) do
    compose = compose_file(dir)

    System.cmd(
      "docker-compose",
      [
        "--profile",
        "validate_2",
        "-f",
        compose,
        "up",
        "-d"
      ],
      @cmd_options
    )
  end

  defp testnet_cleanup(dir, code, address_encoded) do
    Logger.info("#{dir} Cleanup", address: address_encoded)

    System.cmd(
      "docker-compose",
      [
        "-f",
        compose_file(dir),
        "down",
        "--volumes"
      ],
      @cmd_options
    )

    docker([
      "image",
      "rm",
      "-f",
      "archethic-cd",
      "archethic-ci",
      "prom/prometheus"
    ])

    File.rm_rf!(dir)
    code
  end

  defp compose_file(dir), do: Path.join(dir, "docker-compose.json")

  defp temp_dir(prefix, tmp \\ System.tmp_dir!()) do
    {_mega, sec, micro} = :os.timestamp()
    scheduler_id = :erlang.system_info(:scheduler_id)
    Path.join(tmp, "#{prefix}#{:erlang.phash2({sec, micro, scheduler_id})}")
  end
end
