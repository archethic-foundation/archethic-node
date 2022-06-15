defmodule ArchethicWeb.API.Schema.NFTLedger do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Types.Address

  embedded_schema do
    embeds_many :transfers, Transfer do
      field(:to, Address)
      field(:amount, :integer)
      field(:nft, Address)
    end
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [])
    |> cast_embed(:transfers, with: &changeset_transfers/2)
    |> validate_length(:transfers,
      max: 256,
      message: "maximum nft transfers in a transaction can be 256"
    )
  end

  defp changeset_transfers(changeset, params) do
    changeset
    |> cast(params, [:to, :amount, :nft])
    |> validate_required([:to, :amount, :nft])
    |> validate_number(:amount, greater_than: 0)
  end
end
