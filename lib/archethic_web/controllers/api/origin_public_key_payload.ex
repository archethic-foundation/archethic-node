defmodule ArchEthicWeb.API.OriginPublicKeyPayload do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthicWeb.API.Types.Hex
  alias ArchEthicWeb.API.Types.PublicKey

  embedded_schema do
    field(:publicKey, PublicKey)
    field(:certificate, Hex)
  end

  def changeset(params = %{}) do
    %__MODULE__{}
    |> cast(params, [
      :publicKey,
      :certificate
    ])
    |> validate_required([
      :publicKey
    ])
  end
end
