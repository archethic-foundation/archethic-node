defmodule ArchEthicWeb.API.OriginPublicKeyPayload do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthic.Utils

  alias ArchEthicWeb.API.Types.Hex
  alias ArchEthicWeb.API.Types.PublicKey

  embedded_schema do
    field(:PublicKey, PublicKey)
    field(:Certificate, Hex)
  end

  def changeset(params = %{}) do
    %__MODULE__{}
    |> cast(params, [
      :PublicKey,
      :Certificate
    ])
    |> validate_required([
      :PublicKey
    ])
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
end
