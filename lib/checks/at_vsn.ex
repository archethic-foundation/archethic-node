defmodule Archethic.Checks.AtVsn do
  @moduledoc """
  Check that GenServer & GenStateMachine have a @vsn attribute
  """

  use Credo.Check, category: :warning

  defstruct is_a_server: false,
            has_a_at_vsn: false,
            issues: []

  def run(source_file = %SourceFile{}, params = []) do
    # IssueMeta helps keeping track of the source file and the check's params
    # (technically, it's just a custom tagged tuple)
    issue_meta = IssueMeta.for(source_file, params)

    case Credo.Code.prewalk(source_file, &traverse(&1, &2), %__MODULE__{}) do
      %__MODULE__{is_a_server: true, has_a_at_vsn: false} ->
        [format_issue(issue_meta, message: "Missing @vsn attribute")]

      _ ->
        []
    end
  end

  defp traverse(ast = {:use, _, [{:__aliases__, _, [:GenServer]} | _]}, acc) do
    {ast, %__MODULE__{acc | is_a_server: true}}
  end

  defp traverse(ast = {:use, _, [{:__aliases__, _, [:GenStateMachine]} | _]}, acc) do
    {ast, %__MODULE__{acc | is_a_server: true}}
  end

  defp traverse(ast = {:@, _, [{:vsn, _, _}]}, acc) do
    {ast, %__MODULE__{acc | has_a_at_vsn: true}}
  end

  defp traverse(ast, acc) do
    {ast, acc}
  end
end
