defmodule ArchethicWeb.API.Schema.AuthorizedKey do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Types.Hex
  alias ArchethicWeb.API.Types.PublicKey

  embedded_schema do
    field(:publicKey, PublicKey)
    field(:encryptedSecretKey, Hex)
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [:publicKey, :encryptedSecretKey])
    |> validate_required([:publicKey, :encryptedSecretKey])
  end
end
