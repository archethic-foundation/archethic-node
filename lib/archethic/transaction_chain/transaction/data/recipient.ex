defmodule Archethic.TransactionChain.TransactionData.Recipient do
  @moduledoc """
  Represents a call to a Smart Contract

  When the call is to a named action, the recipient is this struct
  When the call is not to a named action, the recipient is a binary (the contract address)
  """
  alias Archethic.Crypto
  alias Archethic.Utils

  defstruct [:address, :action, :args]

  @type t ::
          Crypto.preprended_hash()
          | %__MODULE__{
              address: Crypto.prepended_hash(),
              action: String.t(),
              args: list(any())
            }

  @doc """
  Serialize a recipient
  """
  @spec serialize(t(), pos_integer()) :: binary()
  def serialize(address, _tx_version) when is_binary(address) do
    <<0::8, address::binary>>
  end

  def serialize(%__MODULE__{address: address, action: action, args: args}, _tx_version) do
    # 255 chars should be enough
    action_bytes = byte_size(action)
    true = 255 >= action_bytes

    serialized_args = :erlang.term_to_binary(args, [:compressed])
    args_bytes = byte_size(serialized_args) |> Utils.VarInt.from_value()

    <<1::8, address::binary, action_bytes::8, action::binary, args_bytes::binary,
      serialized_args::binary>>
  end

  @doc """
  Deserialize a recipient
  """
  @spec deserialize(binary(), pos_integer()) :: {t(), binary()}
  def deserialize(<<0::8, rest::binary>>, _tx_version) do
    Utils.deserialize_address(rest)
  end

  def deserialize(<<1::8, rest::binary>>, _tx_version) do
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
end
