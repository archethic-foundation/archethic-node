defmodule ArchEthicWeb.API.Schema.Keys do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthicWeb.API.Schema.AuthorizedKey
  alias ArchEthicWeb.API.Types.Hex

  embedded_schema do
    field(:secret, Hex)
    embeds_many(:authorizedKeys, AuthorizedKey)
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [:secret])
    |> cast_embed(:authorizedKeys)
    |> validate_required([:secret, :authorizedKeys])
  end
end
