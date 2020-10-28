defmodule Uniris.Governance.Code.TestNet.DockerImpl do
  @moduledoc false
  #
  #  @behaviour Uniris.Governance.Code.TestNetImpl
  #
  #  alias Uniris.Governance.Code.Command
  #
  #  require Logger
  #
  #  @doc """
  #  Deploy current testnet workdir into a docker
  #  """
  #  @impl true
  #  def deploy(address, p2p_port, web_port, p2p_seeds)
  #      when is_binary(address) and is_integer(p2p_port) and
  #             is_integer(web_port) and
  #             is_binary(p2p_seeds) do
  #    with :ok <- build_image(address),
  #         :ok <- run_container(address, p2p_port, web_port, p2p_seeds) do
  #      :ok
  #    else
  #      {:error, _} = e ->
  #        clean(address)
  #        e
  #    end
  #  end
  #
  #  defp build_image(address) do
  #    case Command.execute("docker build --build-arg RELEASE_ENV=$RELEASE_ENV -t uniris .",
  #           metadata: [proposal_address: address]
  #         ) do
  #      {:ok, _} ->
  #        :ok
  #
  #      {:error, _} = e ->
  #        e
  #    end
  #  end
  #
  #  # Provide a docker container name for the proposal testnet
  #  defp container_name(address) when is_binary(address) do
  #    "uniris_#{Base.encode16(address, case: :lower)}"
  #  end
  #
  #  defp run_container(address, p2p_port, web_port, p2p_seeds) do
  #    env =
  #      " -e UNIRIS_CRYPTO_SEED=\"node1\" -e UNIRIS_P2P_SEEDS=#{p2p_seeds} -e UNIRIS_DB_BRANCH=#{
  #        Base.encode16(address)
  #      }"
  #
  #    ports = "-p #{p2p_port}:3002 -p #{web_port}:80"
  #    name = "--name #{container_name(address)}"
  #    image = "uniris"
  #
  #    # Add localhost to route the DB access
  #    networking = "--add-host=\"localhost:#{local_ip()}\""
  #
  #    clean(address)
  #
  #    cmd_opts = [metadata: [proposal_address: address]]
  #
  #    case Command.execute("docker run #{env} #{ports} #{networking} #{name} -d #{image}", cmd_opts) do
  #      {:ok, _} ->
  #        :ok
  #
  #      {:error, _} = e ->
  #        e
  #    end
  #  end
  #
  #  @doc """
  #  Clean the docker testnet build
  #  """
  #  @impl true
  #  @spec clean(binary()) :: :ok
  #  def clean(address) do
  #    address
  #    |> container_name
  #    |> clean_image
  #
  #    clean_untagged_images()
  #    :ok
  #  end
  #
  #  # Remove the docker image instance as well as its volume
  #  defp clean_image(container_name) do
  #    Command.execute("docker rm -vf #{container_name}")
  #    :ok
  #  end
  #
  #  defp clean_untagged_images do
  #    {:ok, _} =
  #      Command.execute("docker rmi -f $(docker images | grep \"^<none>\" | awk '{print $3}')")
  #
  #    :ok
  #  end
  #
  #  defp local_ip do
  #    {:ok, ifs} = :inet.getif()
  #
  #    ifs
  #    |> Enum.map(fn {ip, _, _} -> ip end)
  #    |> Enum.reject(&(&1 == {127, 0, 0, 1}))
  #    |> List.first()
  #    |> :inet_parse.ntoa()
  #  end
end
