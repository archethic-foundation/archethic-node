defmodule ArchEthic.P2P.Message.Error do
  @moduledoc """
  Represents an error message
  """

  defstruct [:reason]

  @type reason :: :network_issue | :invalid_transaction | :invalid_attestation

  @type t :: %__MODULE__{
          reason: reason()
        }

  @doc """
  Serialize an error reason
  """
  @spec serialize_reason(reason()) :: non_neg_integer()
  def serialize_reason(:network_issue), do: 0
  def serialize_reason(:invalid_transaction), do: 1
  def serialize_reason(:invalid_attestation), do: 2

  @doc """
  Deserialize an error reason
  """
  @spec deserialize_reason(non_neg_integer()) :: reason()
  def deserialize_reason(0), do: :network_issue
  def deserialize_reason(1), do: :invalid_transaction
  def deserialize_reason(2), do: :invalid_attestation
end
