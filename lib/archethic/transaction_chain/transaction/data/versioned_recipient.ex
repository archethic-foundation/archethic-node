defmodule Archethic.TransactionChain.TransactionData.VersionedRecipient do
  @moduledoc """
  Wrap Recipient struct with the transaction version.
  Usefull when recipient is used alone without link with its transaction
  """
  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionData.Recipient

  defstruct [:address, :action, :args, :tx_version]

  @type t :: %__MODULE__{
          address: Crypto.prepended_hash(),
          action: String.t() | nil,
          args: list(any()) | map() | nil,
          tx_version: non_neg_integer()
        }

  @doc """
  Serialize a versioned recipient
  """
  @spec serialize(
          versioned_recipient :: t(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: bitstring()
  def serialize(recipient, serialization_mode \\ :compact)

  def serialize(verisioned_recipient = %__MODULE__{tx_version: version}, serialization_mode) do
    recipient = unwrap_recipient(verisioned_recipient)
    <<version::32, Recipient.serialize(recipient, version, serialization_mode)::bitstring>>
  end

  @doc """
  Deserialize a recipient
  """
  @spec deserialize(rest :: bitstring(), serialization_mode :: Transaction.serialization_mode()) ::
          {t(), bitstring()}
  def deserialize(binary, serialization_mode \\ :compact)

  def deserialize(<<version::32, rest::bitstring>>, serialization_mode) do
    {recipient, rest} = Recipient.deserialize(rest, version, serialization_mode)
    {wrap_recipient(recipient, version), rest}
  end

  @doc """
  Wrap a recipient into a versioned recipient
  """
  @spec wrap_recipient(recipient :: Recipient.t(), tx_version :: non_neg_integer()) :: t()
  def wrap_recipient(%Recipient{address: address, action: action, args: args}, tx_version),
    do: %__MODULE__{address: address, action: action, args: args, tx_version: tx_version}

  @doc """
  Unwrap a versioned recipient into a recipient
  """
  @spec unwrap_recipient(versioned_recipient :: t()) :: Recipient.t()
  def unwrap_recipient(%__MODULE__{address: address, action: action, args: args}),
    do: %Recipient{address: address, action: action, args: args}
end
