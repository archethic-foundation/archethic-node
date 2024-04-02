defmodule Archethic.P2P.Message.NotifyLastTransactionAddress do
  @moduledoc """
  Represents a message with to notify a pool of the last address of a previous address
  """
  @enforce_keys [:last_address, :genesis_address, :previous_address, :timestamp]
  defstruct [:last_address, :genesis_address, :previous_address, :timestamp]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.SelfRepair
  alias Archethic.P2P
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message

  @type t :: %__MODULE__{
          last_address: Crypto.versioned_hash(),
          genesis_address: Crypto.versioned_hash(),
          previous_address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(
        %__MODULE__{
          genesis_address: genesis_address,
          last_address: last_address,
          previous_address: previous_address,
          timestamp: timestamp
        },
        _
      ) do
    with {local_last_address, _} <- TransactionChain.get_last_address(genesis_address),
         true <- local_last_address != last_address do
      if local_last_address == previous_address do
        TransactionChain.register_last_address(genesis_address, last_address, timestamp)
      else
        authorized_nodes = P2P.authorized_and_available_nodes()
        SelfRepair.update_last_address(local_last_address, authorized_nodes)
      end
    end

    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        last_address: last_address,
        genesis_address: genesis_address,
        previous_address: previous_address,
        timestamp: timestamp
      }) do
    <<last_address::binary, genesis_address::binary, previous_address::binary,
      DateTime.to_unix(timestamp, :millisecond)::64>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {last_address, rest} = Utils.deserialize_address(rest)
    {genesis_address, rest} = Utils.deserialize_address(rest)
    {previous_address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%__MODULE__{
       last_address: last_address,
       genesis_address: genesis_address,
       previous_address: previous_address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end
end
