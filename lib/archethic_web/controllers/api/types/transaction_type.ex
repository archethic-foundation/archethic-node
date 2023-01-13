defmodule ArchethicWeb.API.Types.TransactionType do
  @moduledoc false

  use Ecto.Type

  def type, do: :string

  @authorized_types [
    "keychain_access",
    "keychain",
    "transfer",
    "hosting",
    "token",
    "data",
    "contract",
    "code_proposal",
    "code_approval"
  ]

  def cast(type) when is_binary(type) and type in @authorized_types, do: {:ok, type}
  def cast(_), do: :error

  def load(type), do: type

  def dump(type) when is_atom(type), do: Atom.to_string(type)
  def dump(_), do: :error
end
