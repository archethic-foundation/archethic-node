defmodule Archethic.TransactionChain.TransactionData.Recipient do
  @moduledoc """
  Represents a call to a Smart Contract

  Action & Args are nil for a :transaction trigger and are filled for a {:transaction, action, args} trigger
  """
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils
  alias __MODULE__.ArgumentsEncoding

  defstruct [:address, :action, :args]

  @unnamed_action 0
  @named_action 1

  @type t :: %__MODULE__{
          address: Crypto.prepended_hash(),
          action: String.t() | nil,
          args: list(any()) | map()
        }

  @doc """
  Return wether this is a named action call or not
  """
  @spec is_named_action?(recipient :: t()) :: boolean()
  def is_named_action?(%__MODULE__{action: nil, args: nil}), do: false
  def is_named_action?(%__MODULE__{}), do: true

  @doc """
  Serialize a recipient
  """
  @spec serialize(
          recipient :: t(),
          version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: bitstring()
  def serialize(recipient, version, serialization_mode \\ :compact)

  def serialize(%__MODULE__{address: address}, _version = 1, _serialization_mode) do
    <<address::binary>>
  end

  def serialize(%__MODULE__{address: address, action: nil}, _version, _serialization_mode) do
    <<@unnamed_action::8, address::binary>>
  end

  def serialize(
        %__MODULE__{address: address, action: action, args: args},
        _version = 2,
        _serialization_mode
      ) do
    # action is stored on 8 bytes which means 255 characters
    # we force that in the interpreters (action & condition)
    action_bytes = byte_size(action)

    serialized_args = Jason.encode!(args)

    args_bytes =
      serialized_args
      |> byte_size()
      |> Utils.VarInt.from_value()

    <<@named_action::8, address::binary, action_bytes::8, action::binary, args_bytes::binary,
      serialized_args::bitstring>>
  end

  def serialize(
        %__MODULE__{address: address, action: action, args: args},
        version,
        serialization_mode
      ) do
    # action is stored on 8 bytes which means 255 characters
    # we force that in the interpreters (action & condition)
    action_bytes = byte_size(action)

    serialized_args = ArgumentsEncoding.serialize(args, serialization_mode, version)

    <<@named_action::8, address::binary, action_bytes::8, action::binary,
      serialized_args::bitstring>>
  end

  @doc """
  Deserialize a recipient
  """
  @spec deserialize(
          rest :: bitstring(),
          version :: pos_integer(),
          serialization_mode :: Transaction.serialization_mode()
        ) :: {t(), bitstring()}
  def deserialize(binary, version, serialization_mode \\ :compact)

  def deserialize(rest, _version = 1, _serialization_mode) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end

  def deserialize(<<@unnamed_action::8, rest::bitstring>>, _version, _serialization_mode) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{address: address},
      rest
    }
  end

  def deserialize(<<@named_action::8, rest::bitstring>>, _version = 2, _serialization_mode) do
    {address, <<action_bytes::8, rest::bitstring>>} = Utils.deserialize_address(rest)
    <<action::binary-size(action_bytes), rest::bitstring>> = rest

    {args_bytes, rest} = Utils.VarInt.get_value(rest)
    <<args::binary-size(args_bytes), rest::bitstring>> = rest

    {
      %__MODULE__{
        address: address,
        action: action,
        args: Jason.decode!(args)
      },
      rest
    }
  end

  def deserialize(<<@named_action::8, rest::bitstring>>, version, serialization_mode) do
    {address, <<action_bytes::8, rest::bitstring>>} = Utils.deserialize_address(rest)
    <<action::binary-size(action_bytes), rest::bitstring>> = rest
    {args, rest} = ArgumentsEncoding.deserialize(rest, serialization_mode, version)

    {
      %__MODULE__{
        address: address,
        action: action,
        args: args
      },
      rest
    }
  end

  @doc false
  @spec cast(recipient :: binary() | map()) :: t()
  def cast(recipient) when is_binary(recipient), do: %__MODULE__{address: recipient}

  def cast(recipient = %{address: address}) do
    action = Map.get(recipient, :action)
    args = Map.get(recipient, :args)
    %__MODULE__{address: address, action: action, args: args}
  end

  @doc false
  @spec to_map(recipient :: t()) :: map()
  def to_map(%__MODULE__{address: address, action: action, args: args}),
    do: %{address: address, action: action, args: args}

  @spec to_address(recipient :: t()) :: list(binary())
  def to_address(%{address: address}), do: address
end
