defmodule Uniris.Governance.Code.TestNet do
  @moduledoc false

  # alias Uniris.Governance.Code.Command
  # alias Uniris.Governance.Code.Git
  alias Uniris.Governance.Code.Proposal

  # alias Uniris.P2P.BootstrappingSeeds
  # alias Uniris.PubSub

  # alias Uniris.TransactionChain.Transaction

  require Logger

  @doc """
  Deploy a testnet of the transaction proposal
  """
  @spec deploy_proposal(Proposal.t()) :: :ok | {:error, :deployment_failed}
  def deploy_proposal(_prop = %Proposal{address: _address}) do
    #    :ok = checkout_code(prop)
    #
    #    {p2p_port, web_port} = Proposal.testnet_ports(prop)
    #
    #    p2p_seeds = get_p2p_seeds(p2p_port)
    #
    #    with :ok <- impl().deploy(address, p2p_port, web_port, p2p_seeds),
    #         :ok <- Process.sleep(3000),
    #         :ok <- health_check(web_port) do
    #      PubSub.notify_code_proposal_deployment(address, p2p_port, web_port)
    #      :ok
    #    else
    #      _ ->
    #        patch_file = Git.patch_filename(address)
    #        branch_name = Git.proposal_branch_name(address)
    #
    #        Git.clean(patch_file, branch_name)
    #        impl().clean(address)
    #        {:error, :deployment_failed}
    #    end
    :ok
  end

  #  defp checkout_code(tx = %Transaction{address: address}) do
  #    branch_name = Git.proposal_branch_name(address)
  #
  #    unless Git.branch_exists?(branch_name) do
  #      Git.fork_proposal(tx)
  #    end
  #
  #    Git.switch_branch(branch_name)
  #  end
  #
  #  defp get_p2p_seeds(port) do
  #    BootstrappingSeeds.list()
  #    |> Enum.map(&%{&1 | port: port})
  #    |> BootstrappingSeeds.nodes_to_seeds()
  #  end
  #
  #  defp impl do
  #    :uniris
  #    |> Application.get_env(__MODULE__, impl: __MODULE__.DockerImpl)
  #    |> Keyword.fetch!(:impl)
  #  end

  @doc """
  Performs a health check to ensure the node is running
  """
  @spec health_check(:inet.port_number()) :: :ok | {:error, :unreachable}
  def health_check(web_port) when is_integer(web_port) do
    case System.cmd("curl", [
           "-s",
           "-i",
           "http://localhost:#{web_port}/explorer",
           "|",
           "head",
           "-n",
           "1"
         ]) do
      {"HTTP/1.1 200 OK\n", 0} ->
        :ok

      _ ->
        {:error, :unreachable}
    end
  end
end
