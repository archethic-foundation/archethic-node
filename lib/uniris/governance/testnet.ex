defmodule Uniris.Governance.Testnet do
  @moduledoc false

  alias Uniris.Governance.Command
  alias Uniris.Governance.Git

  alias Uniris.P2P.BootstrapingSeeds

  alias Uniris.Transaction

  require Logger

  @doc """
  Deploy a testnet of the transaction proposal
  """
  @spec deploy(Transaction.t()) :: :ok | {:error, :deployment_failed}
  def deploy(tx = %Transaction{address: address}) do
    {p2p_port, web_port} = ports(tx)

    Logger.debug("Ports: #{p2p_port} #{web_port}")

    branch_name = Git.branch_name(address)

    p2p_seeds =
      BootstrapingSeeds.list()
      |> Enum.map(&%{&1 | port: p2p_port})
      |> BootstrapingSeeds.nodes_to_seeds()

    if Git.branch_exists?(branch_name) do
      Git.switch_branch(branch_name)
      do_deploy(address, p2p_port, web_port, p2p_seeds)
    else
      with :ok <- Git.fork_proposal(tx),
           :ok <- do_deploy(address, p2p_port, web_port, p2p_seeds) do
        :ok
      end
    end
  end

  defp do_deploy(address, p2p_port, web_port, p2p_seeds) do
    with :ok <-
           impl().deploy(address, p2p_port, web_port, p2p_seeds),
         :ok <- Process.sleep(3000) do
      healthcheck(web_port)
      :ok
    else
      _ ->
        Git.clean(address)
        {:error, :deployment_failed}
    end
  end

  defp impl do
    :uniris
    |> Application.get_env(__MODULE__, impl: __MODULE__.Docker)
    |> Keyword.fetch!(:impl)
  end

  @doc """
  Determine testnets ports from the transaction timestamp
  """
  @spec ports(Transaction.t()) ::
          {p2p_port :: :inet.port_number(), web_port :: :inet.port_number()}
  def ports(%Transaction{timestamp: timestamp}) do
    Logger.debug("#{inspect(timestamp)}")

    {
      rem(DateTime.to_unix(timestamp), 12_345),
      rem(DateTime.to_unix(timestamp), 54_321)
    }
  end

  @doc """
  Performs a healthcheck to ensure the node is running
  """
  def healthcheck(web_port) when is_integer(web_port) do
    Command.execute("curl -s -i http://localhost:#{web_port}/explorer | head -n 1")
    |> Enum.to_list()
    |> case do
      ["HTTP/1.1 200 OK"] ->
        :ok

      _ ->
        {:error, :unreachable}
    end
  end
end
