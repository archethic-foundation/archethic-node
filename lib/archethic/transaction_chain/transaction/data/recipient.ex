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
  @spec is_named_action?(t()) :: boolean()
  def is_named_action?(%__MODULE__{action: nil, args: nil}), do: false
  def is_named_action?(%__MODULE__{}), do: true

  @doc """
  Serialize a recipient
  """
  @spec serialize(t(), pos_integer()) :: binary()
  def serialize(%__MODULE__{address: address}, 1) do
    <<address::binary>>
  end

  def serialize(%__MODULE__{address: address, action: nil, args: nil}, 2) do
    <<@unnamed_action::8, address::binary>>
  end

  def serialize(%__MODULE__{address: address, action: action, args: args}, 2) do
    # 255 chars should be enough
    action_bytes = byte_size(action)
    true = 255 >= action_bytes

    serialized_args = :erlang.term_to_binary(args, [:compressed])
    args_bytes = byte_size(serialized_args) |> Utils.VarInt.from_value()

    <<@named_action::8, address::binary, action_bytes::8, action::binary, args_bytes::binary,
      serialized_args::binary>>
  end

  @doc """
  Deserialize a recipient
  """
  @spec deserialize(binary(), pos_integer()) :: {t(), binary()}
  def deserialize(rest, 1) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end

  def deserialize(<<@unnamed_action::8, rest::binary>>, 2) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{address: address},
      rest
    }
  end

  def deserialize(<<@named_action::8, rest::binary>>, 2) do
    {address, <<action_bytes::8, rest::binary>>} = Utils.deserialize_address(rest)
    <<action::binary-size(action_bytes), rest::binary>> = rest

    {args_bytes, rest} = Utils.VarInt.get_value(rest)
    <<args::binary-size(args_bytes), rest::binary>> = rest

    {
      %__MODULE__{
        address: address,
        action: action,
        args: Plug.Crypto.non_executable_binary_to_term(args, [:safe])
      },
      rest
    }
  end

  @doc false
  @spec cast(map()) :: t()
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
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{address: address, action: action, args: args}) do
    %{
      address: address,
      action: action,
      args: args
    }
  end
end
