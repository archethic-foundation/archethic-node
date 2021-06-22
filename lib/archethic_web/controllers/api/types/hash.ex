defmodule ArchEthicWeb.API.Types.Hash do
  @moduledoc false

  use Ecto.Type

  alias ArchEthic.Crypto

  def type, do: :binary

  def cast(hash) when is_binary(hash) do
    with {:ok, binary} <- Base.decode16(hash, case: :mixed),
         true <- Crypto.valid_hash?(binary) do
      {:ok, binary}
    else
      :error ->
        {:error, [message: "must be hexadecimal"]}

      false ->
        {:error, [message: "invalid hash size"]}
    end
  end

  def cast(_), do: {:error, [message: "must be a string"]}

  def load(hash), do: hash

  def dump(hash) when is_binary(hash), do: Base.encode16(hash)
  def dump(_), do: :error
end
