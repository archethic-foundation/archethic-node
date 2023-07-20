defmodule ArchethicWeb.API.Schema.Ledger do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Schema.TokenLedger
  alias ArchethicWeb.API.Schema.UCOLedger

  embedded_schema do
    embeds_one(:uco, UCOLedger)
    embeds_one(:token, TokenLedger)
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [])
    |> cast_embed(:uco)
    |> cast_embed(:token)
  end
end
