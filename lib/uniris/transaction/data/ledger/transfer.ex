defmodule Uniris.TransactionData.Ledger.Transfer do
  @moduledoc """
  Represents any ledger transfer
  """
  defstruct [:to, :amount, :conditions]

  alias Uniris.Crypto

  @typedoc """
  Recipient address of the ledger transfers
  """
  @type recipient :: binary()

  @typedoc """
  Set of conditions to spent the outputs transactions
  """
  @type conditions :: list(binary())

  @typedoc """
  Transfer is composed from:
  - to: receiver address of the asset
  - amount: specify the number of asset to transfer to the recipients
  - conditions: specify to which address the asset can be used
  """
  @type t :: %__MODULE__{
          to: recipient(),
          amount: float(),
          conditions: conditions()
        }

  @doc """
  Serialize transaction transfer into binary format

  ## Examples

      iex> Uniris.TransactionData.Ledger.Transfer.serialize(%Uniris.TransactionData.Ledger.Transfer{
      ...>   to: <<0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...>    85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
      ...>   amount: 10.5
      ...> })
      <<
        # Transfer recipient
        0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
        85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14,
        # Transfer amount
        64, 37, 0, 0, 0, 0, 0, 0
      >>
  """
  def serialize(%__MODULE__{to: to, amount: amount}) do
    <<to::binary, amount::float>>
  end

  @doc """
  Deserialize an encoded transfer

  ## Examples

      iex> <<
      ...> 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...> 85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14,
      ...> 64, 37, 0, 0, 0, 0, 0, 0>>
      ...> |> Uniris.TransactionData.Ledger.Transfer.deserialize()
      {
        %Uniris.TransactionData.Ledger.Transfer{
          to: <<0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
            85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
          amount: 10.5
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {__MODULE__.t(), bitstring}
  def deserialize(<<hash_id::8, rest::bitstring>>) do
    hash_size = Crypto.hash_size(hash_id)
    <<address::binary-size(hash_size), amount::float, rest::bitstring>> = rest

    {
      %__MODULE__{to: <<hash_id::8, address::binary>>, amount: amount},
      rest
    }
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(transfer = %{}) do
    %__MODULE__{
      to: Map.get(transfer, :to),
      amount: Map.get(transfer, :amount)
    }
  end

  @spec to_map(__MODULE__.t()) :: map()
  def to_map(%__MODULE__{to: to, amount: amount}) do
    %{
      to: to,
      amount: amount
    }
  end
end
