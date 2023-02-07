defmodule Archethic.Release.TransformPurge do
  @moduledoc false

  use Distillery.Releases.Appup.Transform

  @default_change {:advanced, []}

  def up(:archethic, _v1, _v2, instructions, _opts), do: transform(instructions, [])

  def up(_, _, _, instructions, _), do: instructions

  def down(:archethic, _v1, _v2, instructions, _opts), do: transform(instructions, [])

  def down(_, _, _, instructions, _), do: instructions

  defp transform([], acc), do: Enum.reverse(acc)

  defp transform([instruction | rest], acc) do
    call = elem(instruction, 0)

    new_instruction =
      case call do
        :update ->
          handle_update(instruction)

        call when call in [:load, :load_module] ->
          handle_load(instruction)

        _ ->
          instruction
      end

    transform(rest, [new_instruction | acc])
  end

  defp handle_update(instruction = {_call, _module, :supervisor}), do: instruction

  defp handle_update({call, module}),
    do: {call, module, @default_change, :brutal_purge, :soft_purge}

  defp handle_update({call, module, change}) when is_tuple(change),
    do: {call, module, change, :brutal_purge, :soft_purge}

  defp handle_update({call, module, deps}) when is_list(deps),
    do: {call, module, @default_change, :brutal_purge, :soft_purge, deps}

  defp handle_update({call, module, change, deps}),
    do: {call, module, change, :brutal_purge, :soft_purge, deps}

  # Other change already contain purge so we don't overwrite them
  defp handle_update(instruction), do: instruction

  defp handle_load({call, module}), do: {call, module, :brutal_purge, :soft_purge, []}

  defp handle_load({call, module, deps}),
    do: {call, module, :brutal_purge, :soft_purge, deps}

  # Other change already contain purge so we don't overwrite them
  defp handle_load(instruction), do: instruction
end
