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
      field(:nft_id, :integer, default: 0)
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
    |> cast(params, [:to, :amount, :nft, :nft_id])
    |> validate_required([:to, :amount, :nft, :nft_id])
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:nft_id, greater_than_or_equal_to: 0)
    |> validate_number(:nft_id, less_than_or_equal_to: 255)
  end
end
