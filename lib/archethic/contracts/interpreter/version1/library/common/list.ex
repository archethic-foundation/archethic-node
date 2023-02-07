defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.List do
  @moduledoc false
  defdelegate take_element_at_index(list, idx), to: Enum, as: :at
end
