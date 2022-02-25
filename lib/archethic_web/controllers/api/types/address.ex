defmodule ArchEthicWeb.API.Types.Address do
  @moduledoc false

  use Ecto.Type

  alias ArchEthic.Crypto

  def type, do: :binary

  def cast(addr) when is_binary(addr) do
    with {:ok, binary} <- Base.decode16(addr, case: :mixed),
         true <- Crypto.valid_address?(binary) do
      {:ok, binary}
    else
      :error ->
        {:error, [message: "must be hexadecimal"]}

      false ->
        {:error, [message: "invalid hash size"]}
    end
  end

  def cast(_), do: {:error, [message: "must be a string"]}

  def load(addr), do: addr

  def dump(addr) when is_binary(addr), do: Base.encode16(addr)
  def dump(_), do: :error
end
