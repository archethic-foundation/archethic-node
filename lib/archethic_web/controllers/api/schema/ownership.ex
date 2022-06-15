defmodule ArchethicWeb.API.Schema.Ownership do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Schema.AuthorizedKey
  alias ArchethicWeb.API.Types.Hex

  embedded_schema do
    field(:secret, Hex)
    embeds_many(:authorizedKeys, AuthorizedKey)
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [:secret])
    |> cast_embed(:authorizedKeys)
    |> validate_required([:secret, :authorizedKeys])
    |> validate_length(:authorizedKeys,
      max: 256,
      message: "maximum number of authorized keys can be 256"
    )
    |> format_authorized_keys()
  end

  defp format_authorized_keys(
         changeset = %Ecto.Changeset{valid?: true, changes: %{authorizedKeys: authorized_keys}}
       ) do
    new_authorized_keys_changesets =
      Enum.reduce(authorized_keys, %{}, fn %Ecto.Changeset{
                                             changes: %{
                                               publicKey: public_key,
                                               encryptedSecretKey: encrypted_secret_key
                                             }
                                           },
                                           acc ->
        Map.put(acc, public_key, encrypted_secret_key)
      end)

    put_in(
      changeset,
      [Access.key(:changes, %{}), Access.key(:authorizedKeys, %{})],
      new_authorized_keys_changesets
    )
  end

  defp format_authorized_keys(changeset), do: changeset
end
