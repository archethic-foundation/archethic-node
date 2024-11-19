defmodule Archethic.P2P.Message.ProofOfReplicationDone do
  @moduledoc false

  @enforce_keys [:address, :proof_of_replication]
  defstruct [:address, :proof_of_replication]

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok
  alias Archethic.TransactionChain.Transaction.ProofOfReplication
  alias Archethic.Utils

  @type t() :: %__MODULE__{
          address: Crypto.prepended_hash(),
          proof_of_replication: ProofOfReplication.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: address, proof_of_replication: proof}, sender_public_key) do
    Mining.add_proof_of_replication(address, proof, sender_public_key)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, proof_of_replication: proof}) do
    <<address::binary, ProofOfReplication.serialize(proof)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {proof, rest} = ProofOfReplication.deserialize(rest)

    {%__MODULE__{address: address, proof_of_replication: proof}, rest}
  end
end
