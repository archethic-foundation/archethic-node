defmodule ArchethicWeb.GraphQLSchema.TransactionAttestation do
  @moduledoc false

  use Absinthe.Schema.Notation

  @desc """
  [TransactionAttestation] represents an attestation when a transaction is successfully validated and stored.
  Few attestations can be received with differents confirmations to ensure a better security of the replication.
  """
  object :transaction_attestation do
    field(:address, :address)
    field(:nb_confirmations, :integer)
    field(:max_confirmations, :integer)
  end
end
