defmodule Uniris.Governance.Git do
  @moduledoc """
  Provide functions to interact with the Git repository
  """

  alias Uniris.Governance.Command

  @doc """
  List the files from a specific branch
  """
  @spec list_branch_files(binary) :: Enumerable.t()
  def list_branch_files(branch_name) when is_binary(branch_name) do
    Command.execute("git ls-tree -r #{branch_name} --name-only")
  end
end
