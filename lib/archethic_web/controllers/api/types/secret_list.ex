defmodule ArchEthicWeb.API.Types.SecretList do
  @moduledoc false

  use Ecto.Type

  def type, do: :array

  def cast(secrets) when is_list(secrets) do
    results =
      Enum.map(secrets, fn secret ->
        case Base.decode16(secret, case: :mixed) do
          {:ok, bin_secret} ->
            bin_secret

          _ ->
            {:error, "must be hexadecimal"}
        end
      end)

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] ->
        {:ok, results}

      errors ->
        {:error, Enum.map(errors, fn {:error, msg} -> {:message, msg} end)}
    end
  end

  def cast(_), do: {:error, [message: "must be an array"]}

  def load(secrets), do: secrets

  def dump(secrets) when is_list(secrets), do: Enum.map(secrets, &Base.encode16/1)
  def dump(_), do: :error
end
