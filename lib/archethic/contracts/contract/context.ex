defmodule Archethic.Contracts.Contract.Context do
  @moduledoc """
  A structure to pass around between nodes that contains details about the contract execution.

  A quick note about datetimes in this struct:

  - datetimes within the `trigger` are truncated to the second: that is a contract requirement.
  - `timestamp` is a datetime (not truncated) but we kept that naming because it is the validation_stamp.timestamp
  """

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Utils.VarInt
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  @enforce_keys [:status, :trigger, :timestamp]
  defstruct [
    :status,
    :trigger,
    :timestamp,
    inputs: []
  ]

  @type status :: :no_output | :tx_output | :failure

  @typedoc """
  Think of trigger as an "instance" of a trigger_type
  """
  @type trigger ::
          {:oracle, Crypto.prepended_hash()}
          | {:transaction, Crypto.prepended_hash(), Recipient.t()}
          | {:datetime, DateTime.t()}
          | {:interval, String.t(), DateTime.t()}

  @type t :: %__MODULE__{
          status: status(),
          trigger: trigger(),
          timestamp: DateTime.t(),
          inputs: list(VersionedUnspentOutput.t())
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        status: status,
        trigger: trigger,
        timestamp: timestamp,
        inputs: inputs
      }) do
    inputs_bin =
      inputs
      |> Enum.map(&VersionedUnspentOutput.serialize/1)
      |> :erlang.list_to_bitstring()

    inputs_len_bin =
      inputs
      |> length()
      |> VarInt.from_value()

    <<serialize_status(status)::8, DateTime.to_unix(timestamp, :millisecond)::64,
      serialize_trigger(trigger)::bitstring, inputs_len_bin::binary, inputs_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {status, <<timestamp::64, rest::bitstring>>} = deserialize_status(rest)

    {trigger, rest} = deserialize_trigger(rest)
    {nb_inputs, rest} = VarInt.get_value(rest)
    {inputs, rest} = deserialize_inputs(rest, nb_inputs, [])

    {%__MODULE__{
       status: status,
       trigger: trigger,
       timestamp: DateTime.from_unix!(timestamp, :millisecond),
       inputs: inputs
     }, rest}
  end

  defp serialize_status(:no_output), do: 0
  defp serialize_status(:tx_output), do: 1
  defp serialize_status(:failure), do: 2

  defp deserialize_status(<<0::8, rest::bitstring>>), do: {:no_output, rest}
  defp deserialize_status(<<1::8, rest::bitstring>>), do: {:tx_output, rest}
  defp deserialize_status(<<2::8, rest::bitstring>>), do: {:failure, rest}

  ##
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
    tx_version = Transaction.version()
    recipient_bin = Recipient.serialize(recipient, tx_version)
    <<4::8, address::binary, recipient_bin::bitstring>>
  end

  ##
  defp deserialize_trigger(<<1::8, rest::bitstring>>) do
    {tx_address, rest} = Utils.deserialize_address(rest)
    {{:oracle, tx_address}, rest}
  end

  defp deserialize_trigger(<<2::8, timestamp::64, rest::bitstring>>) do
    {{:datetime, DateTime.from_unix!(timestamp)}, rest}
  end

  defp deserialize_trigger(<<3::8, cron_size::16, rest::bitstring>>) do
    <<cron::binary-size(cron_size), timestamp::64, rest::bitstring>> = rest

    {{:interval, cron, DateTime.from_unix!(timestamp)}, rest}
  end

  defp deserialize_trigger(<<4::8, rest::bitstring>>) do
    tx_version = Transaction.version()

    {tx_address, rest} = Utils.deserialize_address(rest)
    {recipient, rest} = Recipient.deserialize(rest, tx_version)

    {{:transaction, tx_address, recipient}, rest}
  end

  defp deserialize_inputs(rest, 0, acc), do: {acc, rest}

  defp deserialize_inputs(rest, remaning_inputs, acc) do
    {input, rest} = VersionedUnspentOutput.deserialize(rest)
    deserialize_inputs(rest, remaning_inputs - 1, [input | acc])
  end

  @doc """
  Determines if the contract's context inputs are valid against a list of unspent outputs

  ## Examples

      When the list of inputs are the same than the unspent outputs
        
      iex> %Context{
      ...>   status: :tx_output,
      ...>   trigger: {:datetime, 0},
      ...>   timestamp: ~U[2024-02-02 10:04:10Z],
      ...>   inputs: [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{from: "@Alice1", type: :UCO, amount: 100_000_000}
      ...>     }
      ...>   ]
      ...> }
      ...> |> Context.valid_inputs?(
      ...>   [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{ from: "@Alice1", type: :UCO, amount: 100_000_000}
      ...>     }
      ...>   ]
      ...> )
      true

      When the list of unspent outputs are bigger than the contract's inputs

      iex> %Context{
      ...>   status: :tx_output,
      ...>   trigger: {:datetime, 0},
      ...>   timestamp: ~U[2024-02-02 10:04:10Z],
      ...>   inputs: [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{from: "@Alice1", type: :UCO, amount: 100_000_000}
      ...>     }
      ...>   ]
      ...> }
      ...> |> Context.valid_inputs?(
      ...>   [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{ from: "@Alice1", type: :UCO, amount: 100_000_000}
      ...>     },
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{ from: "@Bob3", type: :UCO, amount: 50_000_000}
      ...>     }
      ...>   ]
      ...> )
      true

      When the contract's input doesn't exists from the unspent output list

      iex> %Context{
      ...>   status: :tx_output,
      ...>   trigger: {:datetime, 0},
      ...>   timestamp: ~U[2024-02-02 10:04:10Z],
      ...>   inputs: [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{from: "@Alice1", type: :UCO, amount: 100_000_000}
      ...>     }
      ...>   ]
      ...> }
      ...> |> Context.valid_inputs?(
      ...>   [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{ from: "@Bob3", type: :UCO, amount: 50_000_000}
      ...>     }
      ...>   ]
      ...> )
      false

      When the contract's input doesn't list any unspent output list

      iex> %Context{
      ...>   status: :tx_output,
      ...>   trigger: {:datetime, 0},
      ...>   timestamp: ~U[2024-02-02 10:04:10Z],
      ...>   inputs: []
      ...> }
      ...> |> Context.valid_inputs?(
      ...>   [
      ...>     %VersionedUnspentOutput{ 
      ...>       unspent_output: %UnspentOutput{ from: "@Bob3", type: :UCO, amount: 50_000_000}
      ...>     }
      ...>   ]
      ...> )
      false
  """
  @spec valid_inputs?(t() | nil, list(VersionedUnspentOutput.t())) :: boolean()
  def valid_inputs?(%__MODULE__{inputs: inputs = [_ | _]}, unspent_outputs = [_ | _]) do
    Enum.all?(inputs, fn input ->
      Enum.any?(unspent_outputs, &(&1 == input))
    end)
  end

  def valid_inputs?(%__MODULE__{inputs: []}, _unspent_outputs = [_ | _]), do: false
  def valid_inputs?(%__MODULE__{inputs: [_ | _]}, _unspent_outputs = []), do: false
  def valid_inputs?(nil, _unspent_outputs), do: true
end
