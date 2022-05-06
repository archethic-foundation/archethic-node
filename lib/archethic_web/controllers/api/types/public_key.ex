defmodule ArchethicWeb.API.Types.PublicKey do
  @moduledoc false

  use Ecto.Type

  alias Archethic.Crypto

  def type, do: :binary

  def cast(public_key) when is_binary(public_key) do
    with {:ok, binary} <- Base.decode16(public_key, case: :mixed),
         true <- Crypto.valid_public_key?(binary) do
      {:ok, binary}
    else
      :error ->
        {:error, [message: "must be hexadecimal"]}

      false ->
        {:error, [message: "invalid key size"]}
    end
  end

  def cast(_), do: {:error, [message: "must be a string"]}

  def load(key), do: key

  def dump(key) when is_binary(key), do: Base.encode16(key)
  def dump(_), do: :error
end
