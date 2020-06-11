defmodule UnirisCore.Transaction.CrossValidationStamp do
  @moduledoc """
  Represent a cross validation stamp validated a validation stamp.

  """

  defstruct [:node_public_key, :signature, :inconsistencies]

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction.ValidationStamp

  @typedoc """
  Any cross validation stamp is composed by:
  - Public key: identity of the node
  - Signature: built from the validation stamp if no inconsistencies or from the list of inconsistencies otherwise
  - Inconsistencies: a list of errors found by a `ValidationStamp.verify/6`
  """
  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          signature: binary(),
          inconsistencies: list()
        }

  @doc """
  Perform a signature of the validation if valid otherwise on the inconsistencies found
  """
  @spec new(ValidationStamp.t(), inconsistencies :: list()) :: __MODULE__.t()
  def new(stamp = %ValidationStamp{}, []) do
    %__MODULE__{
      node_public_key: Crypto.node_public_key(),
      signature: Crypto.sign_with_node_key(stamp),
      inconsistencies: []
    }
  end

  def new(%ValidationStamp{}, inconsistencies) when is_list(inconsistencies) do
    %__MODULE__{
      node_public_key: Crypto.node_public_key(),
      signature: Crypto.sign_with_node_key(inconsistencies),
      inconsistencies: inconsistencies
    }
  end

  @doc """
  Determines if a cross validation stamp is valid.

  According to the presence of inconsistencies, those are verified against the signature,
  otherwise the signature is verified with the validation stamp
  """
  @spec valid?(
          __MODULE__.t(),
          ValidationStamp.t()
        ) :: boolean()
  def valid?(
        %__MODULE__{signature: signature, inconsistencies: [], node_public_key: node_public_key},
        stamp = %ValidationStamp{}
      ) do
    Crypto.verify(signature, stamp, node_public_key)
  end

  def valid?(
        %__MODULE__{
          signature: signature,
          inconsistencies: inconsistencies,
          node_public_key: node_public_key
        },
        _stamp = %ValidationStamp{}
      ) do
    Crypto.verify(signature, inconsistencies, node_public_key)
  end
end
