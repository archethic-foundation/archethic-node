defmodule Archethic.TransactionChain.TransactionData.Recipient do
  @moduledoc """
  Represents a call to a Smart Contract

  Action & Args are nil for a :transaction trigger and are filled for a {:transaction, action, args} trigger
  """
  alias Archethic.Crypto
  alias Archethic.Utils

  defstruct [:address, :action, :args]

  @unnamed_action 0
  @named_action 1

  @type t :: %__MODULE__{
          address: Crypto.prepended_hash(),
          action: String.t(),
          args: list(any())
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
  @spec serialize(recipient :: t(), version :: pos_integer()) :: bitstring()
  def serialize(%__MODULE__{address: address}, _version = 1) do
    <<address::binary>>
  end

  def serialize(%__MODULE__{address: address, action: nil, args: nil}, _version = 2) do
    <<@unnamed_action::8, address::binary>>
  end

  def serialize(%__MODULE__{address: address, action: action, args: args}, _version = 2) do
    # action is stored on 8 bytes which means 255 characters
    # we force that in the interpreters (action & condition)
    action_bytes = byte_size(action)

    serialized_args = Jason.encode!(args)
    args_bytes = byte_size(serialized_args) |> Utils.VarInt.from_value()

    <<@named_action::8, address::binary, action_bytes::8, action::binary, args_bytes::binary,
      serialized_args::binary>>
  end

  @doc """
  Deserialize a recipient
  """
  @spec deserialize(rest :: bitstring(), version :: pos_integer()) :: {t(), bitstring()}
  def deserialize(rest, _version = 1) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end

  def deserialize(<<@unnamed_action::8, rest::bitstring>>, _version = 2) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{address: address},
      rest
    }
  end

  def deserialize(<<@named_action::8, rest::bitstring>>, _version = 2) do
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

  @doc false
  @spec cast(map :: map()) :: t()
  def cast(%{
        address: secret,
        action: authorized_keys,
        args: args
      }) do
    %__MODULE__{
      address: secret,
      action: authorized_keys,
      args: args
    }
  end

  @doc false
  @spec to_map(recipient :: t()) :: map()
  def to_map(%__MODULE__{address: address, action: action, args: args}) do
    %{
      address: address,
      action: action,
      args: args
    }
  end
end
