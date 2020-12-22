defmodule Uniris.Governance.Code do
  @moduledoc """
  Provide functions to handle the code management and deployment
  """

  alias Uniris.Crypto

  alias __MODULE__.CI
  alias __MODULE__.Proposal
  alias __MODULE__.TestNet

  alias Uniris.Governance.Pools

  alias Uniris.P2P

  alias Uniris.Replication

  alias Uniris.TransactionChain

  alias Uniris.Utils

  @src_dir Application.compile_env(:uniris, :src_dir)
  @src_branch Application.compile_env(:uniris, :src_branch)

  @doc """
  List the source files from the master branch
  """
  @spec list_source_files() :: list(binary())
  def list_source_files do
    {files, 0} = System.cmd("git", ["ls-tree", "-r", "HEAD", "--name-only"], cd: @src_dir)
    String.split(files, "\n", trim: true)
  end

  @doc """
  Show the content of a file from the last changes
  """
  @spec file_content(binary()) :: binary()
  def file_content(filename) when is_binary(filename) do
    {content, 0} = System.cmd("git", ["show", "HEAD:#{filename}"], cd: @src_dir)
    String.trim(content)
  end

  @doc """
  Determine if the code proposal can be deployed into testnet
  """
  @spec testnet_deployment?(binary()) :: boolean()
  def testnet_deployment?(proposal_address) when is_binary(proposal_address) do
    storage_nodes =
      Replication.chain_storage_nodes(proposal_address, P2P.list_nodes(availability: :global))

    if Utils.key_in_node_list?(storage_nodes, Crypto.node_public_key(0)) do
      approvals = TransactionChain.list_signatures_for_pending_transaction(proposal_address)
      ratio = length(approvals) / length(Pools.members_of(:technical_council))
      ratio >= Pools.threshold_acceptance_for(:technical_council)
    else
      false
    end
  end

  @doc """
  Deploy the proposal into a dedicated testnet
  """
  @spec deploy_proposal_testnet(Proposal.t()) :: :ok
  defdelegate deploy_proposal_testnet(prop), to: TestNet, as: :deploy_proposal

  @doc """
  Ensure the code proposal is valid according to the defined rules:
  - Version in the code proposal must be a direct successor of the current running version.
  - Git diff/patch must be valid.
  """
  @spec valid_proposal?(Proposal.t()) :: boolean()
  def valid_proposal?(prop = %Proposal{version: version}) do
    with true <- succeessor_version?(current_version(), version),
         true <- applicable_proposal?(prop) do
      true
    else
      _ ->
        false
    end
  end

  @doc """
  Ensure the code proposal is an applicable on the given branch.
  """
  @spec applicable_proposal?(Proposal.t()) :: boolean()
  def applicable_proposal?(
        %Proposal{changes: changes, address: address},
        branch \\ @src_branch,
        src_dir \\ @src_dir
      ) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16()
    prop_file = Path.join(System.tmp_dir!(), "prop_#{random}_#{Base.encode16(address)}")
    File.write!(prop_file, changes)

    cmd_options = [stderr_to_stdout: true, cd: src_dir]
    git = fn args -> System.cmd("git", args, cmd_options) end

    res =
      case status() do
        {:clean, ^branch} ->
          git.(["apply", "--check", prop_file])

        otherwise ->
          {:error, otherwise}
      end

    File.rm(prop_file)

    match?({_, 0}, res)
  end

  @doc """
  Return tuple {state, branch_name} where state could be :clean or :dirty or
  {:error, whatever}
  """
  @spec status() :: {:clean, String.t()} | {:dirty, String.t()} | {:error, any}
  def status(src_dir \\ @src_dir) do
    git = fn args -> System.cmd("git", args, stderr_to_stdout: true, cd: src_dir) end

    case git.(["symbolic-ref", "--short", "HEAD"]) do
      {branch, 0} ->
        case git.(["status", "--porcelain"]) do
          {"", 0} ->
            {:clean, String.trim(branch)}

          {_, 0} ->
            {:dirty, String.trim(branch)}

          otherwise ->
            {:error, otherwise}
        end

      otherwise ->
        {:error, otherwise}
    end
  end

  @doc """
  Return true if version2 is a direct successor of version1.
  Note that build and patch must not be set.

  ## Examples

    iex> Code.succeessor_version?("1.1.1", "1.1.2")
    true

    iex> Code.succeessor_version?("1.1.1", "1.2.0")
    true

    iex> Code.succeessor_version?("1.1.1", "2.0.0")
    true

    iex> Code.succeessor_version?("1.1.1", "1.2.2")
    false

    iex> Code.succeessor_version?("1.1.1", "1.2.1")
    false

    iex> Code.succeessor_version?("1.1.1", "1.1.2-pre0")
    false
  """
  @spec succeessor_version?(binary | Version.t(), binary | Version.t()) :: boolean
  def succeessor_version?(version1, version2)
      when is_binary(version1) and is_binary(version2) do
    succeessor_version?(Version.parse!(version1), Version.parse!(version2))
  end

  def succeessor_version?(
        %Version{major: ma, minor: mi, patch: pa1, pre: [], build: nil},
        %Version{major: ma, minor: mi, patch: pa2, pre: [], build: nil}
      ),
      do: pa1 + 1 == pa2

  def succeessor_version?(
        %Version{major: ma, minor: mi1, patch: _, pre: [], build: nil},
        %Version{major: ma, minor: mi2, patch: 0, pre: [], build: nil}
      ),
      do: mi1 + 1 == mi2

  def succeessor_version?(
        %Version{major: ma1, minor: _, patch: _, pre: [], build: nil},
        %Version{major: ma2, minor: 0, patch: 0, pre: [], build: nil}
      ),
      do: ma1 + 1 == ma2

  def succeessor_version?(%Version{}, %Version{}), do: false

  defp current_version do
    :uniris |> Application.spec(:vsn) |> List.to_string()
  end

  @spec list_proposal_CI_logs(binary()) :: Enumerable.t()
  defdelegate list_proposal_CI_logs(address),
    to: CI,
    as: :list_logs
end
