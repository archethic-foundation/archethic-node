defmodule UnirisWeb.API.Types.AuthorizedKeys do
  @moduledoc false

  use Ecto.Type

  alias Uniris.Crypto

  def type, do: :map

  def cast(authorized_keys) when is_map(authorized_keys) do
    results =
      Enum.map(authorized_keys, fn {public_key, encrypted_key} ->
        with {:public_key, {:ok, bin_public_key}} <-
               {:public_key, Base.decode16(public_key, case: :mixed)},
             {:public_key, true} <- {:public_key, Crypto.valid_public_key?(bin_public_key)},
             {:encrypted_key, {:ok, bin_encrypted_key}} <-
               {:encrypted_key, Base.decode16(encrypted_key, case: :mixed)} do
          {bin_public_key, bin_encrypted_key}
        else
          {:public_key, :error} ->
            {:error, "public key must be hexadecimal"}

          {:public_key, false} ->
            {:error, "public key is invalid"}

          {:encrypted_key, :error} ->
            {:error, "encrypted key must be hexadecimal"}
        end
      end)

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] ->
        {:ok, Enum.into(results, %{})}

      errors ->
        {:error, Enum.map(errors, fn {:error, msg} -> {:message, msg} end)}
    end
  end

  def cast(_), do: {:error, [message: "must be a map"]}

  def load(authorized_keys), do: authorized_keys

  def dump(authorized_keys) when is_map(authorized_keys) do
    Enum.map(authorized_keys, fn {public_key, encrypted_key} ->
      {Base.encode16(public_key), Base.encode16(encrypted_key)}
    end)
  end

  def dump(_), do: :error
end
