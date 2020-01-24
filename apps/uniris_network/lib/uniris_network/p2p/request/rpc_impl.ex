defmodule UnirisNetwork.P2P.Request.RPCImpl do
  @moduledoc false

  @behaviour UnirisNetwork.P2P.Request.Impl

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp

  @spec get_transaction(binary()) :: binary()
  @impl true
  def get_transaction(address) when is_binary(address) do
    {:get_transaction, address: address} |> :erlang.term_to_binary()
  end

  @spec get_transaction_chain(binary()) :: binary()
  @impl true
  def get_transaction_chain(address) when is_binary(address) do
    {:get_transaction_chain, address: address} |> :erlang.term_to_binary()
  end

  @spec get_transaction_and_utxo(binary()) :: binary()
  @impl true
  def get_transaction_and_utxo(address) when is_binary(address) do
    {:get_transaction_and_utxo, address: address} |> :erlang.term_to_binary()
  end

  @spec prepare_validation(Transaction.pending(), list(binary()), binary()) :: binary()
  @impl true
  def prepare_validation(
        tx = %Transaction{},
        validation_nodes_public_keys,
        welcome_node_public_key
      )
      when is_list(validation_nodes_public_keys) and is_binary(welcome_node_public_key) do
    {:prepare_validation,
     transaction: tx,
     validation_node_public_keys: validation_nodes_public_keys,
     welcome_node_public_key: welcome_node_public_key}
    |> :erlang.term_to_binary()
  end

  @spec cross_validate_stamp(binary(), ValidationStamp.t()) :: binary()
  @impl true
  def cross_validate_stamp(address, stamp = %ValidationStamp{}) when is_binary(address) do
    {:cross_validate_stamp, transaction_address: address, validation_stamp: stamp}
    |> :erlang.term_to_binary()
  end

  @spec store_transaction(Transaction.validated()) :: binary()
  @impl true
  def store_transaction(tx = %Transaction{}) do
    {:store_transaction, transaction: tx} |> :erlang.term_to_binary()
  end

  @impl true
  def execute({:get_transaction, address: _address}) do
  end

  def execute({:get_transaction_chain, address: _address}) do
  end

  def execute({:get_transaction_and_utxo, address: _address}) do
  end

  def execute(
        {:prepare_validation,
         transaction: _tx,
         validation_node_public_keys: _validation_nodes,
         welcome_node_public_key: _welcome_node}
      ) do
  end

  def execute(
        {:cross_validate_stamp, transaction_address: _tx_addr, stamp: _stamp = %ValidationStamp{}}
      ) do
  end

  def execute({:store_transaction, transaction: _tx}) do
  end

  def execute(_), do: {:error, :invalid_request}
end
