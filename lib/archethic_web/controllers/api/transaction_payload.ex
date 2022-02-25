defmodule ArchEthicWeb.API.TransactionPayload do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthic.Utils

  alias ArchEthicWeb.API.Types.Address
  alias ArchEthicWeb.API.Types.Hex
  alias ArchEthicWeb.API.Types.PublicKey
  alias ArchEthicWeb.API.Types.TransactionType

  alias ArchEthicWeb.API.Schema.TransactionData

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
  end

  def to_map(changes, acc \\ %{})

  def to_map(%{changes: changes}, acc) do
    Enum.reduce(changes, acc, fn {key, value}, acc ->
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

  defp validate_data(changeset = %Ecto.Changeset{}) do
    validate_change(changeset, :data, fn _, data_changeset ->
      case data_changeset.valid? do
        true -> []
        false -> data_changeset.errors
      end
    end)
  end
end
