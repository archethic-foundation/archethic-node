defmodule Uniris.Governance.Testnet.DockerImpl do
  @moduledoc false

  @behaviour Uniris.Governance.Testnet.Impl

  alias Uniris.Governance.Command

  require Logger

  @doc """
  Deploy current testnet workdir into a docker 
  """
  @impl true
  def deploy(address, p2p_port, web_port, p2p_seeds)
      when is_binary(address) and is_integer(p2p_port) and is_integer(web_port) and
             is_binary(p2p_seeds) do
    Logger.debug("Testnet building on ports: #{p2p_port}(P2P) - #{web_port}(WEB)")

    with :ok <- build_image(address),
         :ok <- run_container(address, p2p_port, web_port, p2p_seeds) do
      :ok
    else
      {:error, reason} = e ->
        Logger.error(reason)
        clean_docker()
        e
    end
  end

  @doc """
  Provide a docker image name from a proposal address
  """
  @spec image_name(binary) :: binary()
  def image_name(address) when is_binary(address) do
    "uniris_#{Base.encode16(address, case: :lower)}"
  end

  defp run_container(address, p2p_port, web_port, p2p_seeds) do
    env =
      " -e UNIRIS_CRYPTO_SEED=\"node1\" -e UNIRIS_P2P_SEEDS=#{p2p_seeds} -e UNIRIS_DB_BRANCH=#{
        Base.encode16(address)
      }"

    ports = "-p #{p2p_port}:3002 -p #{web_port}:80"
    Logger.debug(ports)
    name = "--name #{image_name(address)}"
    image = "#{image_name(address)}"
    # Add localhost to route the DB access
    networking = "--add-host=\"localhost:#{local_ip()}\""
    program = "./run.sh -m foreground"

    address
    |> image_name
    |> clean_image

    Command.execute("docker run #{env} #{ports} #{networking} #{name} -d #{image} #{program}")
    |> Enum.to_list()
    |> case do
      [docker_id] ->
        {:ok, _} = Base.decode16(docker_id, case: :lower)
        :ok
    end
  end

  @doc """
  Remove the docker image instance as well as its volume
  """
  @spec clean_image(binary()) :: :ok
  def clean_image(image_name) when is_binary(image_name) do
    Command.execute("docker rm -vf #{image_name}")
    |> Stream.run()

    :ok
  end

  defp build_image(address) do
    Command.execute("docker build -t #{image_name(address)} .")
    |> Stream.filter(&String.contains?(&1, "Successfully built"))
    |> Enum.to_list()
    |> case do
      [_] ->
        :ok

      _ ->
        :error
    end
  end

  defp clean_docker do
    Command.execute("docker rmi $(docker images | grep \"^<none>\" | awk '{print $3}')")
    |> Stream.run()

    :ok
  end

  defp local_ip do
    {:ok, ifs} = :inet.getif()

    ifs
    |> Enum.map(fn {ip, _broadaddr, _mask} -> ip end)
    |> Enum.reject(&(&1 == {127, 0, 0, 1}))
    |> List.first()
    |> :inet_parse.ntoa()
  end
end
