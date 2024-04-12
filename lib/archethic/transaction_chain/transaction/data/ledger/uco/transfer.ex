defmodule Archethic.TransactionChain.TransactionData.UCOLedger.Transfer do
  @moduledoc """
  Represents a UCO transfer
  """
  defstruct [:to, :amount, conditions: []]

  alias Archethic.Utils

  @typedoc """
  Transfer is composed from:
  - to: receiver address of the UCO
  - amount: specify the number of UCO to transfer to the recipients (in the smallest unit 10^-8)
  - conditions: specify to which address the UCO can be used
  """
  @type t :: %__MODULE__{
          to: binary(),
          amount: non_neg_integer(),
          conditions: list(binary())
        }

  @doc """
  Serialize UCO transfer into binary format

  ## Examples

      iex> %Transfer{
      ...>   to:
      ...>     <<0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117, 85,
      ...>       106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
      ...>   amount: 1_050_000_000
      ...> }
      ...> |> Transfer.serialize(current_transaction_version())
      <<0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117, 85, 106, 43,
        26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14, 0, 0, 0, 0, 62, 149, 186, 128>>
  """
  def serialize(%__MODULE__{to: to, amount: amount}, _tx_version) do
    <<to::binary, amount::64>>
  end

  @doc """
  Deserialize an encoded UCO transfer

  ## Examples

      iex> <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117, 85,
      ...>   106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14, 0, 0, 0, 0, 62, 149,
      ...>   186, 128>>
      ...> |> Transfer.deserialize(current_transaction_version())
      {
        %Transfer{
          to:
            <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117, 85,
              106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
          amount: 1_050_000_000
        },
        ""
      }
  """
  @spec deserialize(data :: bitstring(), tx_version :: pos_integer()) :: {t(), bitstring}
  def deserialize(data, _tx_version) when is_bitstring(data) do
    {address, <<amount::64, rest::bitstring>>} = Utils.deserialize_address(data)

    {
      %__MODULE__{to: address, amount: amount},
      rest
    }
  end

  @spec cast(map()) :: t()
  def cast(transfer = %{}) do
    %__MODULE__{
      to: Map.get(transfer, :to),
      amount: Map.get(transfer, :amount)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{to: to, amount: amount}) do
    %{
      to: to,
      amount: amount
    }
  end
end
