defmodule ArchEthicWeb.API.Schema.TransactionData do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchEthicWeb.API.Schema.Ledger
  alias ArchEthicWeb.API.Schema.Ownership
  alias ArchEthicWeb.API.Types.AddressList
  alias ArchEthicWeb.API.Types.Hex

  embedded_schema do
    field(:code, :string)
    field(:content, Hex)
    embeds_one(:ledger, Ledger)
    embeds_many(:ownerships, Ownership)
    field(:recipients, AddressList)
  end

  def changeset(changeset = %__MODULE__{}, params) do
    changeset
    |> cast(params, [:code, :content, :recipients])
    |> cast_embed(:ledger)
    |> cast_embed(:ownerships)
  end
end
