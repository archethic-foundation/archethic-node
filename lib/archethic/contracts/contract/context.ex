defmodule Archethic.Contracts.Contract.Context do
  @moduledoc """
  A structure to pass around between nodes that contains details about the contract execution.

  A quick note about datetimes in this struct:

  - datetimes within the `trigger` are truncated to the second: that is a contract requirement.
  - `timestamp` is a datetime (not truncated) but we kept that naming because it is the validation_stamp.timestamp
  """

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.TransactionChain.TransactionData.Recipient

  @enforce_keys [:status, :trigger, :timestamp]
  defstruct [
    :status,
    :trigger,
    :timestamp
  ]

  @type status :: :no_output | :tx_output | :failure

  @typedoc """
  Think of trigger as an "instance" of a trigger_type
  """
  @type trigger ::
          {:oracle, Crypto.prepended_hash()}
          | {:transaction, Crypto.prepended_hash()}
          | {:transaction, Crypto.prepended_hash(), Recipient.t()}
          | {:datetime, DateTime.t()}
          | {:interval, String.t(), DateTime.t()}

  @type t :: %__MODULE__{
          status: status(),
          trigger: trigger(),
          timestamp: DateTime.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        status: status,
        trigger: trigger,
        timestamp: timestamp
      }) do
    <<serialize_status(status)::8, DateTime.to_unix(timestamp, :millisecond)::64,
      serialize_trigger(trigger)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {status, <<timestamp::64, rest::binary>>} = deserialize_status(rest)

    {trigger, rest} = deserialize_trigger(rest)

    {%__MODULE__{
       status: status,
       trigger: trigger,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  defp serialize_status(:no_output), do: 0
  defp serialize_status(:tx_output), do: 1
  defp serialize_status(:failure), do: 2

  defp deserialize_status(<<0::8, rest::binary>>), do: {:no_output, rest}
  defp deserialize_status(<<1::8, rest::binary>>), do: {:tx_output, rest}
  defp deserialize_status(<<2::8, rest::binary>>), do: {:failure, rest}

  ##
  defp serialize_trigger({:transaction, address}) do
    <<0::8, address::binary>>
  end

  defp serialize_trigger({:oracle, address}) do
    <<1::8, address::binary>>
  end

  defp serialize_trigger({:datetime, datetime}) do
    <<2::8, DateTime.to_unix(datetime)::64>>
  end

  defp serialize_trigger({:interval, cron, datetime}) do
    cron_size = byte_size(cron)
    <<3::8, cron_size::16, cron::binary, DateTime.to_unix(datetime)::64>>
  end

  defp serialize_trigger({:transaction, address, recipient}) do
    # FIXME: tx_version
    tx_version = 1
    recipient_bin = Recipient.serialize(recipient, tx_version)
    <<4::8, address::binary, recipient_bin::binary>>
  end

  ##
  defp deserialize_trigger(<<0::8, rest::binary>>) do
    {tx_address, rest} = Utils.deserialize_address(rest)
    {{:transaction, tx_address}, rest}
  end

  defp deserialize_trigger(<<1::8, rest::binary>>) do
    {tx_address, rest} = Utils.deserialize_address(rest)
    {{:oracle, tx_address}, rest}
  end

  defp deserialize_trigger(<<2::8, timestamp::64, rest::binary>>) do
    {{:datetime, DateTime.from_unix!(timestamp)}, rest}
  end

  defp deserialize_trigger(<<3::8, cron_size::16, rest::binary>>) do
    <<cron::binary-size(cron_size), timestamp::64, rest::binary>> = rest

    {{:interval, cron, DateTime.from_unix!(timestamp)}, rest}
  end

  defp deserialize_trigger(<<4::8, rest::binary>>) do
    # FIXME: tx_version
    tx_version = 1

    {tx_address, rest} = Utils.deserialize_address(rest)
    {recipient, rest} = Recipient.deserialize(rest, tx_version)

    {{:transaction, tx_address, recipient}, rest}
  end
end
