defmodule ArchethicWeb.API.FunctionCallPayload do
  @moduledoc false
  alias ArchethicWeb.API.Types.Address

  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:contract, Address)
    field(:function, :string)
    field(:args, {:array, :any})
  end

  def changeset(params = %{}) do
    %__MODULE__{}
    |> cast(params, [:contract, :function, :args])
    |> validate_required([:contract, :function])
  end
end
