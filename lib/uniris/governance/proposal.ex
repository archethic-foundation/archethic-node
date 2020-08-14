defmodule Uniris.Governance.Proposal do
  @moduledoc """
  Helpers to get proposal metadata
  """

  @doc ~S"""
  Extract description from the transaction content

  ## Examples

      iex> "Description: My Super Proposal
      ...> Changes:
      ...> diff --git a/lib/uniris/governance.ex b/lib/uniris/governance.ex
      ...> index 30787f1..6535f52 100644
      ...> --- a/lib/uniris/governance.ex
      ...> +++ b/lib/uniris/governance.ex
      ...> @@ -1,107 +1,107 @@"
      ...> |> Uniris.Governance.Proposal.get_description
      "My Super Proposal"
  """
  @spec get_description(binary()) :: binary()
  def get_description(content) when is_binary(content) do
    case Regex.scan(~r/(?<=Description:).+?(?=Changes:)/s, content) do
      [description_match] ->
        description_match
        |> List.first()
        |> String.trim()

      [] ->
        ""
    end
  end

  @doc ~S"""
  Extract changes from the transaction content

  ## Examples

      iex> "
      ...> Description: My Super Proposal
      ...> Changes:
      ...> diff --git a/lib/uniris/governance.ex b/lib/uniris/governance.ex
      ...> index 30787f1..6535f52 100644
      ...> --- a/lib/uniris/governance.ex
      ...> +++ b/lib/uniris/governance.ex
      ...> @@ -1,107 +1,107 @@
      ...> "
      ...> |> Uniris.Governance.Proposal.get_changes
      "diff --git a/lib/uniris/governance.ex b/lib/uniris/governance.ex
       index 30787f1..6535f52 100644
       --- a/lib/uniris/governance.ex
       +++ b/lib/uniris/governance.ex
       @@ -1,107 +1,107 @@"
  """
  @spec get_changes(binary()) :: binary()
  def get_changes(content) when is_binary(content) do
    case Regex.scan(~r/(?<=Changes:).*/s, content) do
      [changes_match] ->
        changes_match
        |> List.first()
        |> String.trim()

      [] ->
        ""
    end
  end
end
