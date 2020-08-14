defmodule Uniris.Governance.Git do
  @moduledoc """
  Provide functions to interact with the Git repository
  """

  alias Uniris.Governance.Command
  alias Uniris.Governance.Proposal

  alias Uniris.Transaction
  alias Uniris.TransactionData

  @root_dir Application.get_env(:uniris, :src_dir)

  @doc """
  List the files from a specific branch
  """
  @spec list_branch_files(binary) :: Enumerable.t()
  def list_branch_files(branch_name) when is_binary(branch_name) do
    Command.execute("git ls-tree -r #{branch_name} --name-only")
  end

  @doc """
  Remove the Git branch. 
  """
  @spec remove_branch(binary) :: :ok | :error
  def remove_branch(branch_name) when is_binary(branch_name) do
    Command.execute("git branch -D #{branch_name}")
    |> Enum.into([], fn res -> to_string(res) end)
    |> case do
      [<<"Deleted branch", _::binary>>] ->
        :ok

      _ ->
        :error
    end
  end

  @doc """
  List all the Git branch in the system
  """
  @spec list_branches() :: Enumerable.t()
  def list_branches do
    Command.execute("git branch -l")
    |> Stream.map(&to_string/1)
    |> Stream.map(&String.trim/1)
    |> Stream.map(fn branch ->
      case branch do
        <<"* ", name::binary>> ->
          name

        _ ->
          branch
      end
    end)
  end

  @doc """
  Create a new Git branch
  """
  @spec new_branch(binary) :: :ok
  def new_branch(branch_name) when is_binary(branch_name) do
    Command.execute("git checkout -b #{branch_name}")
    |> Enum.into([], fn res -> to_string(res) end)
    |> case do
      [<<"Switched to", _::binary>> | _] ->
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Change the current branch
  """
  @spec switch_branch(binary()) :: :ok
  def switch_branch(branch_name) when is_binary(branch_name) do
    Command.execute("git checkout #{branch_name}")
    |> Enum.into([], fn res -> to_string(res) end)
    |> case do
      [<<"Switched to", _::binary>> | _] ->
        :ok

      _ ->
        :error
    end
  end

  @doc """
  Apply the patch or diff from a file to the current branch
  """
  @spec apply_patch(binary) :: :ok | :error
  def apply_patch(patch_file) when is_binary(patch_file) do
    if File.exists?(patch_file) do
      Command.execute("git apply #{patch_file}")
      |> Enum.into([], fn res -> to_string(res) end)
      |> case do
        [] ->
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
  @spec revert_patch(binary) :: :ok | :error
  def revert_patch(patch_file) when is_binary(patch_file) do
    if File.exists?(patch_file) do
      Command.execute("git apply -R #{patch_file}")
      |> Enum.into([], fn res -> to_string(res) end)
      |> case do
        [] ->
          :ok

        _ ->
          :error
      end
    else
      :error
    end
  end

  @doc """
  Add the files to the Git stage area to prepare the commit
  """
  @spec add_files(list(binary)) :: :ok | :error
  def add_files(files) when is_list(files) do
    Command.execute("git add #{Enum.join(files, " ")}")
    |> Enum.into([], fn res -> to_string(res) end)
    |> case do
      [] ->
        Command.execute("git diff --name-only --cached")
        |> Enum.into([], fn res -> to_string(res) end)
        |> case do
          staged_files when staged_files == files ->
            :ok

          _ ->
            :error
        end
    end
  end

  @doc """
  Apply the changes to Git by committing the changes
  """
  @spec commit_changes(binary) :: :ok | :error
  def commit_changes(message) when is_binary(message) do
    Command.execute("git commit -m \"#{message}\"")
    |> Stream.take(1)
    |> Enum.into([], fn res -> to_string(res) end)
    |> case do
      [res] ->
        if String.contains?(res, message) do
          :ok
        else
          :error
        end

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
    :ok = remove_patch_file(address)
    :ok = switch_branch("master")
    Process.sleep(1000)

    address
    |> branch_name
    |> remove_branch
  end

  @doc """
  Return the branch of the proposal
  """
  @spec branch_name(binary()) :: binary()
  def branch_name(address) when is_binary(address) do
    "prop_#{Base.encode16(address)}"
  end

  defp remove_patch_file(address) do
    File.rm(patch_filename(address))
  end

  defp patch_filename(address) do
    Path.join(@root_dir, "proposal_#{Base.encode16(address)}.patch")
  end

  @doc """
  Determine if a Git branch exists
  """
  @spec branch_exists?(binary()) :: boolean()
  def branch_exists?(branch_name) when is_binary(branch_name) do
    branch_name in list_branches()
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
    branch = branch_name(address)

    if branch_exists?(branch) do
      switch_branch(branch)
    else
      new_branch(branch)
    end

    case apply_changes(address, content) do
      :ok ->
        :ok

      :error ->
        clean(address)
        :error
    end
  end

  # Apply the change from a diff for given code proposal address.
  # It create a diff patch to leverage `git apply` command
  # and commit the change will be trigger local continous integration through git hooks
  defp apply_changes(address, content) do
    patch_file = patch_filename(address)
    changes = Proposal.get_changes(content)
    :ok = File.write!(patch_file, changes <> "\n")

    files_involved = Proposal.list_files(changes)

    case apply_patch(patch_file) do
      :ok ->
        :ok = add_files(files_involved)

        content
        |> Proposal.get_description()
        |> commit_changes
        |> case do
          :ok ->
            :ok

          :error ->
            revert_patch(patch_file)
            :error
        end

      :error ->
        :error
    end
  end
end
