defmodule ArchethicWeb.API.Schema.TransactionData do
  @moduledoc false
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)
  @code_max_size Application.compile_env!(:archethic, :transaction_data_code_max_size)

  use Ecto.Schema
  import Ecto.Changeset

  alias ArchethicWeb.API.Schema.Ledger
  alias ArchethicWeb.API.Schema.Ownership
  alias ArchethicWeb.API.Types.Hex
  alias ArchethicWeb.API.Types.RecipientList

  embedded_schema do
    field(:code, :string)
    field(:content, Hex)
    embeds_one(:ledger, Ledger)
    embeds_many(:ownerships, Ownership)
    field(:recipients, RecipientList)
  end

  def changeset(changeset = %__MODULE__{}, params) do
    changeset
    |> cast(params, [:code, :content, :recipients])
    |> cast_embed(:ledger)
    |> cast_embed(:ownerships)
    |> validate_length(:content,
      max: @content_max_size,
      message: "content size must be less than content_max_size",
      count: :bytes
    )
    |> validate_length(:code,
      max: @code_max_size,
      message: "code size can't be more than #{Integer.to_string(@code_max_size)} bytes",
      count: :bytes
    )
    |> validate_length(:ownerships, max: 255, message: "ownerships can not be more that 255")
    |> validate_length(:recipients,
      max: 255,
      message: "maximum number of recipients can be 255"
    )
  end
end
