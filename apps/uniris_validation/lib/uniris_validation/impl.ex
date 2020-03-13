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
              validation_node_views :: bitstring(),
              storage_node_views :: bitstring()
            ) :: :ok

  @callback set_replication_tree(binary(), list(bitstring())) :: :ok

  @callback replicate_transaction(Transaction.validated()) ::
              :ok | {:error, :invalid_transaction} | {:error, :invalid_transaction_chain}
end
