defmodule Archethic.P2P.Message.ProofOfValidationDone do
  @moduledoc false

  @enforce_keys [:address, :proof_of_validation]
  defstruct [:address, :proof_of_validation]

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.Utils

  @type t() :: %__MODULE__{
          address: Crypto.prepended_hash(),
          proof_of_validation: ProofOfValidation.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: address, proof_of_validation: proof}, sender_public_key) do
    Mining.add_proof_of_validation(address, proof, sender_public_key)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, proof_of_validation: proof}) do
    <<address::binary, ProofOfValidation.serialize(proof)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {proof, rest} = ProofOfValidation.deserialize(rest)

    {%__MODULE__{address: address, proof_of_validation: proof}, rest}
  end
end
