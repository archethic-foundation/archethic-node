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
    |> cast_embed(:authorizedKeys, required: [:publicKey, :encryptedSecretKey])
    |> validate_required([:secret])
    |> validate_length(:authorizedKeys,
      max: 255,
      message: "maximum number of authorized keys can be 255"
    )
  end
end
