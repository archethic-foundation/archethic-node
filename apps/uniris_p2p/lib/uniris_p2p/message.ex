defmodule UnirisP2P.Message do
  @moduledoc false

  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisValidation, as: Validation
  alias UnirisChain, as: Chain

  require Logger

  @doc """
  Encode a message in binary format with an embedded signature and public key
  to ensure the authenticity of the message
  """
  @spec encode(term()) :: binary()
  def encode(payload) do
    binary_payload = :erlang.term_to_binary(payload)
    {:ok, public_key} = Crypto.last_public_key(:node)
    {:ok, sig} = Crypto.sign(binary_payload, source: :node, label: :last)
    public_key <> sig <> binary_payload
  end

  @doc """
  Decode a encoded message by first verifying its signature and then decode the binary
  """
  @spec decode(binary()) :: {:ok, term(), public_key :: <<_::264>>} | {:error, :invalid_payload}
  def decode(<<public_key::binary-33, signature::binary-64, binary_payload::binary>>) do
    case Crypto.verify(signature, binary_payload, public_key) do
      :ok ->
        payload = :erlang.binary_to_term(binary_payload, [:safe])
        {:ok, payload, public_key}

      _ ->
        {:error, :invalid_payload}
    end
  end

  def decode(_), do: {:error, :invalid_payload}

  @doc """
  Process message coming from a P2P request. Act as P2P message controller
  """
  @spec process(message :: tuple(), node_public_key :: binary()) ::
          {:ok, term()} | {:error, atom()}
  def process({:get_transaction, tx_address}, _from) do
    Chain.get_transaction(tx_address)
  end

  def process({:get_transaction_chain, tx_address}, _from) do
    Chain.get_transaction_chain(tx_address)
  end

  def process({:get_unspent_outputs, tx_address}, _from) do
    Chain.get_unspent_outputs(tx_address)
  end

  def process({:get_proof_of_integrity, tx_address}, _from) do
    with {:ok, %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}}} <-
           Chain.get_transaction(tx_address) do
      {:ok, poi}
    end
  end

  def process(
        {:start_validation, tx = %Transaction{}, welcome_node_public_key, validation_nodes},
        _from
      ) do
    Validation.start_validation(tx, welcome_node_public_key, validation_nodes)
  end

  def process({:replicate_transaction, tx = %Transaction{}}, _from) do
    Validation.replicate_transaction(tx)
  end

  def process({:cross_validate, tx_address, stamp = %ValidationStamp{}}, _from)
      when is_binary(tx_address) do
    Validation.cross_validate(tx_address, stamp)
  end

  def process({:cross_validation_node, tx_address, {signature, inconsistencies}}, from)
      when is_binary(tx_address) and is_binary(signature) and is_list(inconsistencies) do
    Validation.add_cross_validation_stamp(tx_address, {signature, inconsistencies}, from)
  end

  def process(msg, from) do
    Logger.info("Node #{from} send an invalid message: #{inspect(msg)}")
    {:error, :invalid_message}
  end
end
