defmodule ArchEthicWeb.API.Schema.NFTLedger do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthicWeb.API.Types.Hash

  embedded_schema do
    embeds_many :transfers, Transfer do
      field(:to, Hash)
      field(:amount, :integer)
      field(:nft, Hash)
    end
  end

  def changeset(changeset = %__MODULE__{}, params = %{}) do
    changeset
    |> cast(params, [])
    |> cast_embed(:transfers, with: &changeset_transfers/2)
  end

  defp changeset_transfers(changeset, params) do
    changeset
    |> cast(params, [:to, :amount, :nft])
    |> validate_required([:to, :amount, :nft])
    |> validate_number(:amount, greater_than: 0)
  end
end
