defmodule ArchEthic.P2P.Message.Error do
  @moduledoc """
  Represents an error message
  """

  defstruct [:reason]

  @type reason :: :invalid_transaction | :network_issue

  @type t :: %__MODULE__{
          reason: reason()
        }

  @doc """
  Serialize an error reason
  """
  @spec serialize_reason(reason()) :: non_neg_integer()
  def serialize_reason(:network_issue), do: 0
  def serialize_reason(:invalid_transaction), do: 1

  @doc """
  Deserialize an error reason
  """
  @spec deserialize_reason(non_neg_integer()) :: reason()
  def deserialize_reason(0), do: :network_issue
  def deserialize_reason(1), do: :invalid_transaction
end
