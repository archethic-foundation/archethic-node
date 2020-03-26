defmodule UnirisValidation.Impl do
  @moduledoc false

  @callback start_mining(Transaction.pending(), UnirisCrypto.key(), list(UnirisCrypto.key())) ::
              {:ok, pid()}

  @callback cross_validate(address :: binary(), stamp :: ValidationStamp.t()) ::
              {signature :: binary(), inconsistencies :: list(atom())}

  @callback add_cross_validation_stamp(
              address :: binary(),
              stamp ::
                {signature :: binary(), inconsistencies :: list(atom),
                 public_key :: UnirisCrypto.key()}
            ) :: :ok

  @callback add_context(
              address :: binary(),
              validation_node_public_key :: UnirisCrypto.key(),
              previous_storage_nodes :: list(UnirisCrypto.key()),
              validation_nodes_view :: bitstring(),
              chain_storage_nodes_view :: bitstring(),
              beacon_storage_nodes_view :: bitstring()
            ) :: :ok

  @callback set_replication_trees(binary(), list(list(bitstring()))) :: :ok

  @callback replicate_chain(Transaction.validated()) :: :ok
  @callback replicate_transaction(Transaction.validated()) :: :ok
  @callback replicate_address(binary(), non_neg_integer()) :: :ok

  @callback get_proof_of_work(Transaction.pending()) :: {:ok, UnirisCrypto.key()} | {:error, :not_found}
  @callback get_proof_of_integrity(list(Transaction.pending())) :: binary()
  @callback get_transaction_fee(Transaction.pending()) :: float()
  @callback get_node_rewards(float(), UnirisCrypto.key(), UnirisCrypto.key(), list(UnirisCrypto.key()), list(UnirisCrypto.key())) :: list({UnirisCrypto.key(), float()})
  @callback get_cross_validation_stamp(ValidationStamp.t(), list(atom())) :: {binary(), list(atom()), UnirisCrypto.key()}

end
