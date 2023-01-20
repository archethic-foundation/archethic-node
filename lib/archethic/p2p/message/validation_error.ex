defmodule Archethic.P2P.Message.ValidationError do
  @moduledoc """
  Represents an error message
  """
  alias ArchethicWeb.TransactionSubscriber
  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  defstruct [:context, :reason, :address]

  @type t :: %__MODULE__{
          context: :invalid_transaction | :network_issue,
          reason: binary(),
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{context: context, reason: reason, address: address}, _) do
    TransactionSubscriber.report_error(address, context, reason)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{context: :network_issue, reason: reason, address: address}) do
    <<address::binary, reason |> byte_size() |> VarInt.from_value()::binary, reason::binary,
      0::8>>
  end

  def serialize(%__MODULE__{context: :invalid_transaction, reason: reason, address: address}) do
    <<address::binary, reason |> byte_size() |> VarInt.from_value()::binary, reason::binary,
      1::8>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {reason_size, rest} = VarInt.get_value(rest)

    case rest do
      <<reason::binary-size(reason_size), 0::8, rest::bitstring>> ->
        {%__MODULE__{reason: reason, context: :network_issue, address: address}, rest}

      <<reason::binary-size(reason_size), 1::8, rest::bitstring>> ->
        {%__MODULE__{reason: reason, context: :invalid_transaction, address: address}, rest}
    end
  end
end
