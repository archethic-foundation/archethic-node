defmodule Uniris.Governance.Code.CI do
  @moduledoc false

  alias Uniris.Governance.Code.Proposal

  @src_dir Application.compile_env(:uniris, :src_dir)

  @doc """
  Execute the continuous integration of the code proposal in a containerized environment
  """
  @spec run(Proposal.t()) :: :ok
  def run(prop = %Proposal{}) do
    :ok = set_patch(prop)
    :ok = containerize_integration(prop)
  end

  defp set_patch(%Proposal{address: address, changes: changes}) do
    patch_filename = "prop_#{Base.encode16(address)}.patch"
    File.write!(Path.join(@src_dir, patch_filename), changes <> "\n")
  end

  defp containerize_integration(%Proposal{address: address}) do
    cmd_options = [stderr_to_stdout: true, into: IO.stream(:stdio, :line), cd: @src_dir]

    {_, 0} = System.cmd("docker", ["build", "-t", docker_image_name(address), "."], cmd_options)

    {res, 0} =
      System.cmd(
        "docker",
        ["run", "--entrypoint", "scripts/proposal_ci_job.sh", "uniris"],
        cmd_options
      )

    container_id = String.replace_trailing(res, "\n", "")

    Task.start(fn ->
      {_, 0} =
        System.cmd("docker", ["logs", "--timestamps", "--follow", container_id], cmd_options)
    end)

    {_, 0} = System.cmd("docker", ["wait", container_id])
    :ok
  end

  @doc """
  Return the list of logs of the container from the proposal address
  """
  @spec list_logs(binary()) :: list(binary())
  def list_logs(address) when is_binary(address) do
    container_id =
      address
      |> docker_image_name()
      |> last_container_id()

    {res, 0} = System.cmd("docker", ["logs", container_id])

    res
    |> String.replace_trailing("\n", "")
    |> String.split("\n", trim: true)
  end

  defp last_container_id(image) do
    {res, 0} =
      System.cmd("docker", ["ps", "-a", "--filter", "ancestor=#{image}", "--format", "{{.ID}}"])

    String.replace_trailing(res, "\n", "")
  end

  defp docker_image_name(address) do
    "uniris_prop_#{Base.encode16(address)}"
  end
end
