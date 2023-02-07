defmodule Archethic.Contracts.Interpreter.Version1.Library.Common.Map do
  @moduledoc false
  defdelegate get(map, key, default), to: Map, as: :get
  defdelegate put(map, key, value), to: Map, as: :put
end
