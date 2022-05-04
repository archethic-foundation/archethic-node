defmodule ArchethicWeb.API.Schema.Ledger do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Schema.NFTLedger
  alias ArchethicWeb.API.Schema.UCOLedger

  embedded_schema do
    embeds_one(:uco, UCOLedger)
    embeds_one(:nft, NFTLedger)
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [])
    |> cast_embed(:uco)
    |> cast_embed(:nft)
  end
end
