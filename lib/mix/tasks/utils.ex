defmodule Mix.Tasks.Utils do
  @moduledoc false

  def apply_function_if_key_exists(opts, key, func, args) do
    if opts[key] do
      apply(func, args)
    else
      :ok
    end
  end
end
