defmodule Archethic.Governance.Code do
  @moduledoc """
  Provide functions to handle the code management and deployment
  """

  alias Archethic.Crypto

  alias Archethic.Election

  alias __MODULE__.CICD
  alias __MODULE__.Proposal

  alias Archethic.Governance.Pools

  alias Archethic.P2P

  alias Archethic.TransactionChain

  alias Archethic.Utils

  @src_dir Application.compile_env(:archethic, :src_dir)

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
      Election.chain_storage_nodes(proposal_address, P2P.authorized_and_available_nodes())

    if Utils.key_in_node_list?(storage_nodes, Crypto.first_node_public_key()) do
      approvals = TransactionChain.get_signatures_for_pending_transaction(proposal_address)
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
  defdelegate deploy_proposal_testnet(prop), to: CICD, as: :run_testnet!

  @doc """
  Ensure the code proposal is valid according to the defined rules:
  - Version in the code proposal must be a direct successor of the current running version.
  - Git diff/patch must be valid.
  """
  @spec valid_proposal?(Proposal.t()) :: boolean()
  def valid_proposal?(prop = %Proposal{version: version, changes: changes}) do
    current_version = current_version()

    with true <- successor_version?(current_version, version),
         true <- valid_appup?(changes, version, current_version),
         true <- applicable_proposal?(prop) do
      true
    else
      _ ->
        false
    end
  end

  @doc """
    Ensure the code proposal contains a valid appup file
  """
  @spec valid_appup?(binary(), binary(), binary()) :: boolean()
  def valid_appup?(changes, version, current_version) do
    with {:ok, patches} <- GitDiff.parse_patch(changes),
         %GitDiff.Patch{chunks: chunks} <-
           Enum.find(
             patches,
             &(String.starts_with?(&1.to, "rel/appups/archethic") and
                 String.ends_with?(&1.to, ".appup"))
           ),
         %GitDiff.Chunk{lines: lines} <- Enum.at(chunks, 0),
         code_txt <-
           Enum.reduce(lines, "", fn
             %GitDiff.Line{type: :add, text: "+" <> text}, acc ->
               acc <> text

             _, acc ->
               acc
           end),
         {:ok, {version_char, up_instructions, down_instructions}} <- eval_str(code_txt <> "\n"),
         true <- version == to_string(version_char),
         current_version_char_up <-
           Enum.map(up_instructions, &elem(&1, 0))
           |> Enum.uniq(),
         current_version_char_down <-
           Enum.map(down_instructions, &elem(&1, 0))
           |> Enum.uniq(),
         true <- current_version == to_string(current_version_char_up),
         true <- current_version == to_string(current_version_char_down),
         :ok <-
           up_instructions
           |> Enum.map(&elem(&1, 1))
           |> List.flatten()
           |> Distillery.Releases.Appup.Utils.validate_instructions(),
         :ok <-
           down_instructions
           |> Enum.map(&elem(&1, 1))
           |> List.flatten()
           |> Distillery.Releases.Appup.Utils.validate_instructions() do
      true
    else
      _ -> false
    end
  end

  # working around a bug in typespecs for :erl_eval.eval_str
  defp eval_str(str) do
    bin = :erlang.binary_to_list(str)

    {:done, {:ok, token, _}, []} = :erl_scan.tokens([], bin, 0)
    {:ok, expr} = :erl_parse.parse_exprs(token)

    {:value, val, _} =
      :erl_eval.exprs(
        expr,
        :erl_eval.new_bindings(),
        {:value, &catch_function_calls/2},
        {:value, &catch_function_calls/2}
      )

    {:ok, val}
  end

  defp catch_function_calls(_func_name, _args),
    do: throw("Appup file contained calls to a function which is not permitted")

  @doc """
  Ensure the code proposal is an applicable on the current branch.
  """
  @spec applicable_proposal?(Proposal.t()) :: boolean()
  def applicable_proposal?(
        proposal,
        src_dir \\ @src_dir
      ) do
    res = apply_diff(proposal, src_dir, false)
    match?({_, 0}, res)
  end

  defp apply_diff(
         %Proposal{changes: changes, address: address},
         src_dir,
         persist?
       ) do
    prop_file = Path.join(System.tmp_dir!(), "prop_#{Base.encode16(address)}")
    File.write!(prop_file, changes)

    cmd_options = [stderr_to_stdout: true, cd: src_dir]
    git = fn args -> System.cmd("git", args, cmd_options) end

    git_args =
      if persist? do
        ["apply", prop_file]
      else
        ["apply", "--check", prop_file]
      end

    res =
      case status() do
        {:clean, _} ->
          git.(git_args)

        otherwise ->
          {:error, otherwise}
      end

    File.rm(prop_file)
    res
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

    iex> Code.successor_version?("1.1.1", "1.1.2")
    true

    iex> Code.successor_version?("1.1.1", "1.2.0")
    true

    iex> Code.successor_version?("1.1.1", "2.0.0")
    true

    iex> Code.successor_version?("1.1.1", "1.2.2")
    false

    iex> Code.successor_version?("1.1.1", "1.2.1")
    false

    iex> Code.successor_version?("1.1.1", "1.1.2-pre0")
    false
  """
  @spec successor_version?(binary | Version.t(), binary | Version.t()) :: boolean
  def successor_version?(version1, version2)
      when is_binary(version1) and is_binary(version2) do
    successor_version?(Version.parse!(version1), Version.parse!(version2))
  end

  def successor_version?(
        %Version{major: ma, minor: mi, patch: pa1, pre: [], build: nil},
        %Version{major: ma, minor: mi, patch: pa2, pre: [], build: nil}
      ),
      do: pa1 + 1 == pa2

  def successor_version?(
        %Version{major: ma, minor: mi1, patch: _, pre: [], build: nil},
        %Version{major: ma, minor: mi2, patch: 0, pre: [], build: nil}
      ),
      do: mi1 + 1 == mi2

  def successor_version?(
        %Version{major: ma1, minor: _, patch: _, pre: [], build: nil},
        %Version{major: ma2, minor: 0, patch: 0, pre: [], build: nil}
      ),
      do: ma1 + 1 == ma2

  def successor_version?(%Version{}, %Version{}), do: false

  defp current_version do
    :archethic |> Application.spec(:vsn) |> List.to_string()
  end

  @spec list_proposal_CI_logs(binary()) :: Enumerable.t()
  defdelegate list_proposal_CI_logs(address), to: CICD, as: :get_log
end
