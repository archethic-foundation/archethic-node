defmodule ArchethicWeb.API.TransactionPayload do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Archethic.Utils

  alias ArchethicWeb.API.Types.Address
  alias ArchethicWeb.API.Types.Hex
  alias ArchethicWeb.API.Types.PublicKey
  alias ArchethicWeb.API.Types.TransactionType

  alias ArchethicWeb.API.Schema.TransactionData

  embedded_schema do
    field(:version, :integer)
    field(:address, Address)
    field(:type, TransactionType)
    embeds_one(:data, TransactionData)
    field(:previousPublicKey, PublicKey)
    field(:previousSignature, Hex)
    field(:originSignature, Hex)
  end

  def changeset(params = %{}) do
    %__MODULE__{}
    |> cast(params, [
      :version,
      :address,
      :type,
      :previousPublicKey,
      :previousSignature,
      :originSignature
    ])
    |> validate_required([
      :version,
      :address,
      :type,
      :previousPublicKey,
      :previousSignature,
      :originSignature
    ])
    |> cast_embed(:data, required: true)
    |> validate_data()
    |> then(&{:ok, &1})
  end

  def changeset(_params), do: :error

  def to_map(changes, acc \\ %{})

  def to_map(%{changes: changes}, acc) do
    Enum.reduce(changes, acc, fn {key, value}, acc ->
      value = format_change(key, value)

      key = Macro.underscore(Atom.to_string(key))

      case value do
        %{changes: _} ->
          Map.put(acc, key, to_map(value))

        value when is_list(value) ->
          Map.put(acc, key, Enum.map(value, &to_map/1))

        _ ->
          Map.put(acc, key, value)
      end
    end)
    |> Utils.atomize_keys()
  end

  def to_map(value, _), do: value

  defp format_change(:authorizedKeys, authorized_keys) do
    Enum.reduce(authorized_keys, %{}, fn %Ecto.Changeset{
                                           changes: %{
                                             publicKey: public_key,
                                             encryptedSecretKey: encrypted_secret_key
                                           }
                                         },
                                         acc ->
      Map.put(acc, public_key, encrypted_secret_key)
    end)
  end

  defp format_change(_, value), do: value

  defp validate_data(changeset = %Ecto.Changeset{}) do
    validate_change(changeset, :data, fn _, data_changeset ->
      case data_changeset.valid? do
        true -> []
        false -> data_changeset.errors
      end
    end)
  end
end
