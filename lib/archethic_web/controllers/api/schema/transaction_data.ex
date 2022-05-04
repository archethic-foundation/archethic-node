defmodule ArchethicWeb.API.Schema.TransactionData do
  @moduledoc false
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Schema.Ledger
  alias ArchethicWeb.API.Schema.Ownership
  alias ArchethicWeb.API.Types.AddressList
  alias ArchethicWeb.API.Types.Hex

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

  defp validate_content_size(changeset = %Ecto.Changeset{}) do
    validate_change(changeset, :content, fn field, content ->
      content_size = byte_size(content)

      if content_size >= @content_max_size do
        [{field, "content size must be lessthan content_max_size"}]
      else
        []
      end
    end)
  end
end
