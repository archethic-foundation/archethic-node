defmodule ArchEthic.P2P.Message.Error do
  @moduledoc """
  Represents an error message
  """

  defstruct [:reason]

  @type reason ::
          :network_issue
          | :invalid_transaction
          | :invalid_attestation
          | :transaction_already_exists

  @type t :: %__MODULE__{
          reason: reason()
        }

  use ArchEthic.P2P.Message, message_id: 238

  def encode(%__MODULE__{reason: reason}) do
    <<reason_to_id(reason)::8>>
  end

  @spec decode(<<_::8, _::_*1>>) :: {ArchEthic.P2P.Message.Error.t(), bitstring}
  def decode(<<reason_id::8, rest::bitstring>>) do
    {
      %__MODULE__{reason: id_to_reason(reason_id)},
      rest
    }
  end

  def process(%__MODULE__{}) do
  end

  defp reason_to_id(:network_issue), do: 0
  defp reason_to_id(:invalid_transaction), do: 1
  defp reason_to_id(:invalid_attestation), do: 2
  defp reason_to_id(:transaction_already_exists), do: 3

  defp id_to_reason(0), do: :network_issue
  defp id_to_reason(1), do: :invalid_transaction
  defp id_to_reason(2), do: :invalid_attestation
  defp id_to_reason(3), do: :transaction_already_exists
end
