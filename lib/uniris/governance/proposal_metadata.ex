defmodule Uniris.Governance.ProposalMetadata do
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
      ...> |> Uniris.Governance.ProposalMetadata.get_description
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
      ...> |> Uniris.Governance.ProposalMetadata.get_changes
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

  @doc """
  Return the list of files created/updated/removed from the proposal changes (ie. Git Diff)

  ## Examples
      iex> Uniris.Governance.ProposalMetadata.list_files("diff --git a/lib/uniris/self_repair.ex b/lib/uniris/self_repair.ex
      ...> index 124088f..c3add90 100755
      ...> --- a/lib/uniris/self_repair.ex")
      ["lib/uniris/self_repair.ex"]
  """
  @spec list_files(binary()) :: list(binary())
  def list_files(changes = <<"diff --git", _::binary>>) do
    String.split(changes, "\n")
    |> Enum.filter(&String.starts_with?(&1, "diff --git"))
    |> Enum.map(&get_file_from_diff_string/1)
    |> Enum.flat_map(& &1)
  end

  # Analyse a diff and extract the files impacted (add/update/delete)
  defp get_file_from_diff_string(str) do
    str
    |> String.split(" ")
    |> Enum.filter(&(String.starts_with?(&1, "a/") or String.starts_with?(&1, "b/")))
    |> Enum.map(fn file ->
      case file do
        <<"a/", file::binary>> ->
          file

        <<"b/", file::binary>> ->
          file
      end
    end)
    |> Enum.uniq()
  end

  @doc ~S"""
  Retrieve the version update in the changes of the proposal

  ## Examples

      iex> Uniris.Governance.ProposalMetadata.get_version("
      ...> diff --git a/mix.exs b/mix.exs
      ...> index d9d9a06..5e34b89 100644
      ...> --- a/mix.exs
      ...> +++ b/mix.exs
      ...> @@ -4,7 +4,7 @@ defmodule Uniris.MixProject do
      ...>   def project do
      ...>     [
      ...>       app: :uniris,
      ...> -      version: \"0.7.1\",
      ...> +      version: \"0.7.2\",
      ...>       build_path: \"_build\",
      ...>       config_path: \"config/config.exs\",
      ...>       deps_path: \"deps\",
      ...> @@ -53,7 +53,7 @@ defmodule Uniris.MixProject do
      ...>       {:git_hooks, \"~> 0.4.0\", only: [:test, :dev], runtime: false},
      ...>       {:mox, \"~> 0.5.2\", only: [:test]},
      ...>       {:stream_data, \"~> 0.4.3\", only: [:test]},
      ...> -      {:elixir_make, \"~> 0.6.0\", only: [:dev, :test], runtime: false},
      ...> +      {:elixir_make, \"~> 0.6.0\", only: [:dev, :test]},
      ...>       {:logger_file_backend, \"~> 0.0.11\", only: [:dev]}
      ...>     ]
      ...>   end
      ...> ")
      {:ok, "0.7.2"}
  """
  @spec get_version(binary()) :: {:ok, binary()} | {:error, :missing_version}
  def get_version(changes) do
    case Regex.scan(~r/(?<=\+      version: )[^,]*/, changes) do
      [version_match] ->
        new_version =
          version_match
          |> List.first()
          |> String.trim()
          |> String.replace("\"", "")

        {:ok, new_version}

      _ ->
        {:error, :missing_version}
    end
  end
end
