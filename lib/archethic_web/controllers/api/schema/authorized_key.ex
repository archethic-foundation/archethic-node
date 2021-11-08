defmodule ArchEthicWeb.API.Schema.AuthorizedKey do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthicWeb.API.Types.Hex
  alias ArchEthicWeb.API.Types.PublicKey

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
