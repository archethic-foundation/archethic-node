defmodule Uniris.Governance.Git do
  @moduledoc """
  Provide functions to interact with the Git repository
  """

  alias Uniris.Governance.Command
  alias Uniris.Governance.ProposalMetadata

  alias Uniris.Transaction
  alias Uniris.TransactionData

  @doc """
  List the files from a specific branch
  """
  @spec list_branch_files(binary) :: list(binary())
  def list_branch_files(branch_name) when is_binary(branch_name) do
    {:ok, files} = Command.execute("git ls-tree -r #{branch_name} --name-only", log?: false)
    files
  end

  @doc """
  Create a new Git branch
  """
  @spec new_branch(binary, binary()) :: :ok
  def new_branch(branch_name, address) when is_binary(branch_name) and is_binary(address) do
    {:ok, _} =
      Command.execute(
        "git checkout -b #{branch_name}",
        metadata: [proposal_address: Base.encode16(address)],
        cd: cd_dir(address)
      )

    :ok
  end

  @doc """
  Apply the patch or diff from a file to the current branch
  """
  @spec apply_patch(binary, binary) :: :ok
  def apply_patch(patch_file, address) when is_binary(patch_file) and is_binary(address) do
    if File.exists?(Path.join(cd_dir(address), patch_file)) do
      case Command.execute(
             "git apply #{patch_file}",
             metadata: [proposal_address: Base.encode16(address)],
             cd: cd_dir(address)
           ) do
        {:ok, _} ->
          :ok

        _ ->
          :error
      end
    else
      :error
    end
  end

  @doc """
  Cancel the changes from the patch
  """
  @spec revert_patch(binary, binary) :: :ok | :error
  def revert_patch(patch_file, address) when is_binary(patch_file) and is_binary(address) do
    if File.exists?(patch_file) do
      {:ok, _} =
        Command.execute(
          "git apply -R #{patch_file}",
          metadata: [proposal_address: Base.encode16(address)],
          cd: cd_dir(address)
        )

      :ok
    else
      :error
    end
  end

  @doc """
  Add the files to the Git stage area to prepare the commit
  """
  @spec add_files(list(binary), binary()) :: :ok
  def add_files(files, address) when is_list(files) and is_binary(address) do
    {:ok, _} =
      Command.execute(
        "git add #{Enum.join(files, " ")}",
        metadata: [proposal_address: Base.encode16(address)],
        cd: cd_dir(address)
      )

    :ok
  end

  @doc """
  Apply the changes to Git by committing the changes
  """
  @spec commit_changes(binary, binary) :: :ok | :error
  def commit_changes(message, address) when is_binary(message) and is_binary(address) do
    case Command.execute(
           "git commit -m \"#{message}\"",
           metadata: [proposal_address: Base.encode16(address)],
           cd: cd_dir(address)
         ) do
      {:ok, _} ->
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Clean the repository with the temporary patch:
  - removing patch file
  - removing branch
  - switch to master
  """
  @spec clean(proposal_address :: binary()) :: :ok
  def clean(address) when is_binary(address) do
    {:ok, _} = Command.execute("rm -rf #{cd_dir(address)}")
  end

  @doc """
  Return the branch of the proposal
  """
  @spec branch_name(binary()) :: binary()
  def branch_name(address) when is_binary(address) do
    "prop_#{Base.encode16(address)}"
  end

  defp patch_filename(address) do
    "#{Base.encode16(address)}.patch"
  end

  @doc """
  Fork the changes in the transaction code proposal by appling
  the git diff in a dedicated branch and commit the changes triggering the continuous integration
  """
  @spec fork_proposal(Transaction.t()) :: :ok | {:error, :invalid_changes}
  def fork_proposal(%Transaction{
        address: address,
        type: :code_proposal,
        data: %TransactionData{content: content}
      }) do
    File.rm_rf(cd_dir(address))
    {:ok, _} = Command.execute("git clone . #{cd_dir(address)}")

    new_branch(branch_name(address), address)

    case apply_changes(address, content) do
      :ok ->
        :ok

      :error ->
        clean(address)
        {:error, :invalid_changes}
    end
  end

  # Apply the change from a diff for given code proposal address.
  # It create a diff patch to leverage `git apply` command
  # and commit the change will be trigger local continous integration through git hooks
  defp apply_changes(address, content) do
    patch_file = patch_filename(address)
    changes = ProposalMetadata.get_changes(content)
    :ok = File.write!(Path.join(cd_dir(address), patch_file), changes <> "\n")

    files_involved = ProposalMetadata.list_files(changes)

    case apply_patch(patch_file, address) do
      :ok ->
        :ok = add_files(files_involved, address)

        content
        |> ProposalMetadata.get_description()
        |> commit_changes(address)
        |> case do
          :ok ->
            :ok

          :error ->
            revert_patch(patch_file, address)
            :error
        end

      :error ->
        :error
    end
  end

  def cd_dir(address) when is_binary(address),
    do: Application.app_dir(:uniris, "priv/#{branch_name(address)}")
end
