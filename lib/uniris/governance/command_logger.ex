defmodule Uniris.Governance.CommandLogger do
  @moduledoc false

  @behaviour __MODULE__.Impl

  @spec write(binary, Keyword.t()) :: :ok
  @impl true
  def write(data, metadata)
      when is_binary(data) and is_list(metadata) do
    impl().write(data, metadata)
  end

  defp impl do
    :uniris
    |> Application.get_env(__MODULE__, impl: __MODULE__.FileImpl)
    |> Keyword.fetch!(:impl)
  end
end
