defmodule Archethic.Release.ParseContractCode do
  @moduledoc false

  alias Archethic.Contracts.Loader

  use Distillery.Releases.Appup.Transform

  def up(:archethic, _v1, _v2, instructions, _opts),
    do: add_contract_reparse(instructions)

  def up(_, _, _, instructions, _), do: instructions

  def down(_, _, _, instructions, _), do: instructions

  defp add_contract_reparse(instructions) do
    call_instruction = {:apply, {Loader, :reparse_workers_contract, []}}

    instructions ++ [call_instruction]
  end
end
