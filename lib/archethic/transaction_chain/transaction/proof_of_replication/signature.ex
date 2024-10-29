defmodule Archethic.TransactionChain.Transaction.ProofOfReplication.Signature do
  @moduledoc """
  Structure to hold a node proof of replication signature.  
  Contains:
  - signature: the BLS signature
  - node mining key: the node mining key which match the signature
  - node public key: the node public key which created the signature
  """

  alias Archethic.Utils
  alias Archethic.Crypto
  alias Archethic.TransactionChain.TransactionSummary

  @enforce_keys [:signature, :node_mining_key, :node_public_key]
  defstruct [:signature, :node_mining_key, :node_public_key]

  @type t :: %__MODULE__{
          signature: binary(),
          node_mining_key: Crypto.key(),
          node_public_key: Crypto.key()
        }

  @bls_signature_size 96

  @doc """
  Create a proof of replication signature using the node's mining private key to
  sign the transaction summary
  """
  @spec create(transaction_summary :: TransactionSummary.t()) :: signature :: t()
  def create(transaction_summary) do
    signature =
      transaction_summary |> TransactionSummary.serialize() |> Crypto.sign_with_mining_node_key()

    %__MODULE__{
      signature: signature,
      node_mining_key: Crypto.mining_node_public_key(),
      node_public_key: Crypto.first_node_public_key()
    }
  end

  @doc """
  Returns true if the mining public key match the signature using the transaction summary
  """
  @spec valid?(signature :: t(), transaction_summary :: TransactionSummary.t()) :: boolean()
  def valid?(%__MODULE__{signature: signature, node_mining_key: public_key}, transaction_summary) do
    raw_data = TransactionSummary.serialize(transaction_summary)
    Crypto.verify?(signature, raw_data, public_key)
  end

  @spec serialize(signature :: t()) :: bitstring()
  def serialize(%__MODULE__{
        signature: signature,
        node_mining_key: mining_key,
        node_public_key: public_key
      }),
      do: <<signature::binary-size(@bls_signature_size), mining_key::binary, public_key::binary>>

  @spec deserialize(bin :: bitstring()) :: {signature :: t(), rest :: bitstring()}
  def deserialize(<<signature::binary-size(@bls_signature_size), rest::bitstring>>) do
    {mining_key, rest} = Utils.deserialize_public_key(rest)
    {public_key, rest} = Utils.deserialize_public_key(rest)

    sig = %__MODULE__{
      signature: signature,
      node_mining_key: mining_key,
      node_public_key: public_key
    }

    {sig, rest}
  end
end
