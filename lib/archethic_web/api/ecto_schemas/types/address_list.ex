defmodule ArchethicWeb.API.Types.AddressList do
  @moduledoc false

  use Ecto.Type

  alias Archethic.Crypto

  def type, do: :array

  def cast(addresses) when is_list(addresses) do
    results =
      Enum.map(addresses, fn address ->
        with {:ok, bin_address} <- Base.decode16(address, case: :mixed),
             true <- Crypto.valid_address?(bin_address) do
          bin_address
        else
          :error ->
            {:error, "must be hexadecimal"}

          false ->
            {:error, "invalid hash"}
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

  def load(addresses), do: addresses

  def dump(addresses) when is_list(addresses), do: Enum.map(addresses, &Base.encode16/1)
  def dump(_), do: :error
end
