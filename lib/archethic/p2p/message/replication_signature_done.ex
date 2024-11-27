defmodule Archethic.P2P.Message.ReplicationSignatureDone do
  @moduledoc false

  defstruct [:address, :replication_signature]

  use Retry

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.Ok
  alias Archethic.TransactionChain.Transaction.ProofOfReplication.Signature
  alias Archethic.Utils

  require Logger

  @type t() :: %__MODULE__{
          address: Crypto.prepended_hash(),
          replication_signature: Signature.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          address: address,
          replication_signature:
            replication_signature = %Signature{
              node_mining_key: node_mining_key,
              node_public_key: node_public_key
            }
        },
        from
      ) do
    with true <- node_public_key == from,
         %Node{mining_public_key: ^node_mining_key} <- P2P.get_node_info!(from) do
      Mining.add_replication_signature(address, replication_signature)
    else
      _ ->
        Logger.warning(
          "Received invalid replication signature done message from #{Base.encode16(from)}"
        )
    end

    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, replication_signature: signature}) do
    <<address::binary, Signature.serialize(signature)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {signature, rest} = Signature.deserialize(rest)

    {%__MODULE__{address: address, replication_signature: signature}, rest}
  end
end
