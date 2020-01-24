defmodule UnirisNetwork.P2P.Request.Impl do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidatedStamp

  @callback get_transaction(address :: binary()) :: binary()
  @callback get_transaction_chain(address :: binary()) :: binary()
  @callback get_transaction_and_utxo(address :: binary()) :: binary()
  @callback prepare_validation(
              Transaction.pending(),
              validation_node_public_keys :: list(binary()),
              welcome_node_public_key :: binary()
            ) :: binary()
  @callback cross_validate_stamp(address :: binary(), ValidationStamp.t()) :: binary()
  @callback store_transaction(Transaction.validated()) :: binary()

  @callback execute(term()) :: {:ok, term()} | {:error, :invalid_request}
end
