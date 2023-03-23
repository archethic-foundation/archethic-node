defmodule Archethic.Release.CallMigrateScript do
  @moduledoc false

  alias Mix.Tasks.Archethic.Migrate

  use Distillery.Releases.Appup.Transform

  def up(:archethic, _v1, v2, instructions, _opts),
    do: add_migrate_script_call(v2, instructions)

  def up(_, _, _, instructions, _), do: instructions

  def down(_, _, _, instructions, _), do: instructions

  defp add_migrate_script_call(new_version, instructions) do
    call_instruction = {:apply, {Migrate, :run, [new_version]}}

    instructions ++ [call_instruction]
  end
end
