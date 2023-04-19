defmodule Archethic.Checks.NamedSupervisor do
  @moduledoc """
  Check that supervisor has a name
  """

  use Credo.Check, category: :warning

  defstruct supervisor?: false, named?: false

  def run(source_file = %SourceFile{}, params = []) do
    # IssueMeta helps keeping track of the source file and the check's params
    # (technically, it's just a custom tagged tuple)
    issue_meta = IssueMeta.for(source_file, params)

    case Credo.Code.prewalk(source_file, &traverse(&1, &2), %__MODULE__{}) do
      %__MODULE__{supervisor?: true, named?: false} ->
        [format_issue(issue_meta, message: "Supervisor must be named")]

      _ ->
        []
    end
  end

  defp traverse(ast = {:use, _, [{:__aliases__, _, [:Supervisor]} | _]}, acc) do
    {ast, %__MODULE__{acc | supervisor?: true}}
  end

  defp traverse(
         ast =
           {{:., _,
             [
               {:__aliases__, _, [:Supervisor]},
               :start_link
             ]}, _, sup_ast},
         acc = %__MODULE__{supervisor?: true}
       ) do
    case sup_ast do
      [
        {:__MODULE__, _, nil},
        _,
        [name: _]
      ] ->
        {ast, %__MODULE__{acc | named?: true}}

      [
        {:__MODULE__, _, nil},
        [name: _]
      ] ->
        {ast, %__MODULE__{acc | named?: true}}

      _ ->
        {ast, acc}
    end
  end

  defp traverse(ast, acc), do: {ast, acc}
end
