defmodule ArchethicWeb.API.Schema.TransactionData do
  @moduledoc false
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)
  @code_max_size Application.compile_env!(:archethic, :transaction_data_code_max_size)

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
    |> validate_length(:content,
      max: @content_max_size,
      message: "content size must be lessthan content_max_size"
    )
    |> validate_length(:code,
      max: @code_max_size,
      message: "code size can't be more than #{Integer.to_string(@code_max_size)} bytes"
    )
    |> validate_length(:ownerships, max: 256, message: "ownerships can not be more that 256")
    |> validate_length(:recipients, max: 256, message: "maximum number of recipients can be 256")
  end
end
