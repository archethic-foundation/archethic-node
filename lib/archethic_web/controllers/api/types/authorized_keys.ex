defmodule ArchEthicWeb.API.Types.AuthorizedKeys do
  @moduledoc false

  use Ecto.Type

  alias ArchEthic.Crypto

  def type, do: :array

  def cast(authorized_keys) when is_list(authorized_keys) do
    results = Enum.map(authorized_keys, &do_cast/1)

    case Enum.flat_map(results, & &1) |> Enum.filter(&match?({:error, _}, &1)) do
      [] ->
        {:ok, results}

      errors ->
        {:error, Enum.map(errors, fn {:error, msg} -> {:message, msg} end)}
    end
  end

  def cast(_), do: {:error, [message: "must be an array"]}

  defp do_cast(keys_by_secrets) do
    Enum.map(keys_by_secrets, fn {public_key, encrypted_key} ->
      with {:public_key, {:ok, bin_public_key}} <-
             {:public_key, Base.decode16(public_key, case: :mixed)},
           {:public_key, true} <- {:public_key, Crypto.valid_public_key?(bin_public_key)},
           {:encrypted_key, {:ok, bin_encrypted_key}} <-
             {:encrypted_key, Base.decode16(encrypted_key, case: :mixed)},
           {:encrypted_key_size, :ok} <-
             {:encrypted_key_size, check_encrypted_key_size(bin_public_key, bin_encrypted_key)} do
        {bin_public_key, bin_encrypted_key}
      else
        {:public_key, :error} ->
          {:error, "public key must be hexadecimal"}

        {:public_key, false} ->
          {:error, "public key is invalid"}

        {:encrypted_key, :error} ->
          {:error, "encrypted key must be hexadecimal"}

        {:encrypted_key_size, :error} ->
          {:error, "encrypted key size is invalid"}
      end
    end)
    |> Enum.into(%{})
  end

  def load(authorized_keys), do: authorized_keys

  def dump(authorized_keys) when is_list(authorized_keys) do
    Enum.map(authorized_keys, fn authorized_keys_by_secret ->
      Enum.map(authorized_keys_by_secret, fn {public_key, encrypted_key} ->
        {Base.encode16(public_key), Base.encode16(encrypted_key)}
      end)
      |> Enum.into(%{})
    end)
  end

  def dump(_), do: :error

  defp check_encrypted_key_size(<<0::8, _::binary>>, encrypted_key)
       when byte_size(encrypted_key) == 80 do
    :ok
  end

  defp check_encrypted_key_size(<<0::8, _::binary>>, _) do
    :error
  end

  defp check_encrypted_key_size(<<_::8, _::binary>>, encrypted_key)
       when byte_size(encrypted_key) == 113 do
    :ok
  end

  defp check_encrypted_key_size(<<_::8, _::binary>>, _) do
    :error
  end
end
