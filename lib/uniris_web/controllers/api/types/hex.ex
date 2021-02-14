defmodule UnirisWeb.API.Types.Hex do
  @moduledoc false

  use Ecto.Type

  def type, do: :binary

  def cast(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} ->
        {:ok, binary}

      _ ->
        {:error, [message: "must be hexadecimal"]}
    end
  end

  def cast(_), do: {:error, [message: "must be a string"]}

  def load(hex), do: hex

  def dump(hex) when is_binary(hex), do: Base.encode16(hex)
  def dump(_), do: :error
end
