defmodule UnirisNetwork.P2P.Request do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisNetwork.P2P.Payload
  alias UnirisNetwork.P2P.NodeView

  @behaviour UnirisNetwork.P2P.Request.Impl

  @impl true
  @spec get_transaction(address :: binary()) :: binary()
  def get_transaction(address) when is_binary(address) do
    impl().get_transaction(address) |> Payload.encode()
  end

  @impl true
  @spec get_transaction_chain(address :: binary()) :: binary()
  def get_transaction_chain(address) when is_binary(address) do
    impl().get_transaction_chain(address) |> Payload.encode()
  end

  @impl true
  @spec get_transaction_and_utxo(address :: binary()) :: binary()
  def get_transaction_and_utxo(address) when is_binary(address) do
    impl().get_transaction_and_utxo(address) |> Payload.encode()
  end

  @impl true
  @spec prepare_validation(
          Transaction.pending(),
          validation_node_public_keys :: list(binary()),
          welcome_node_public_key :: binary()
        ) :: binary()
  def prepare_validation(
        tx = %Transaction{},
        validation_node_public_keys,
        welcome_node_public_key
      )
      when is_list(validation_node_public_keys) and is_binary(welcome_node_public_key) do
    impl().prepare_validation(tx, validation_node_public_keys, welcome_node_public_key)
    |> Payload.encode()
  end

  @impl true
  @spec cross_validate_stamp(address :: binary(), ValidationStamp.t()) :: binary()
  def cross_validate_stamp(address, stamp = %ValidationStamp{}) when is_binary(address) do
    impl().cross_validate_stamp(address, stamp) |> Payload.encode()
  end

  @impl true
  @spec store_transaction(Transaction.validated()) :: binary()
  def store_transaction(tx = %Transaction{}) do
    impl().store_transaction(tx) |> Payload.encode()
  end

  @impl true
  @spec execute(term()) :: {:ok, term()} | {:error, :invalid_request} | {:error, atom()}
  def execute(request) do
    impl().execute(request)
  end


  defp impl(), do: Application.get_env(:uniris_network, :request_handler, UnirisNetwork.P2P.Request.RPCImpl)

end
