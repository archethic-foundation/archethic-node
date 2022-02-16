defmodule ArchEthicWeb.API.Schema.TransactionData do
  @moduledoc false
  @content_max_size Application.get_env(:archethic, :transaction_data_content_max_size)

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
    |> validate_content_size()
  end

  defp validate_content_size(%Ecto.Changeset{} = changeset) do
    content = Map.get(changeset.changes, :content)
    content_size = byte_size(content) / (1024 * 1024)

    if content_size >= @content_max_size do
      add_error(
        changeset,
        :content,
        "Content size cannot be greater than #{@content_max_size} MB"
      )
    else
      changeset
    end
  end
end
