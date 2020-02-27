defmodule UnirisP2P.Message do
  @moduledoc false

  alias UnirisCrypto, as: Crypto
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisValidation, as: Validation
  alias UnirisChain, as: Chain
  alias UnirisNetwork, as: Network
  alias UnirisNetwork.Node
  alias UnirisElection, as: Election

  require Logger

  @doc """
  Encode a message in binary format with an embedded signature and public key
  to ensure the authenticity of the message
  """
  @spec encode(term()) :: binary()
  def encode(payload) do
    binary_payload = :erlang.term_to_binary(payload)
    public_key = Crypto.last_node_public_key()
    sig = Crypto.sign(binary_payload, with: :node, as: :last)
    public_key <> sig <> binary_payload
  end

  @doc """
  Decode a encoded message by first verifying its signature and then decode the binary
  """
  @spec decode(binary()) :: {:ok, term(), public_key :: <<_::binary-32>>} | {:error, :invalid_payload}
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
  Process message coming from a P2P request by actin as a message controller/broker providing an Anti Corruption Layer
  """
  @spec process(message :: tuple(), node_public_key :: binary()) ::
          {:ok, term()} | {:error, atom()}
  def process({:get_transaction, tx_address}, _from) when is_binary(tx_address) do
    Chain.get_transaction(tx_address)
  end

  def process({:get_transaction_chain, tx_address}, _from) when is_binary(tx_address) do
    Chain.get_transaction_chain(tx_address)
  end

  def process({:get_unspent_outputs, tx_address}, _from) when is_binary(tx_address) do
    Chain.get_unspent_outputs(tx_address)
  end

  def process({:get_proof_of_integrity, tx_address}, _from) when is_binary(tx_address) do
    with {:ok, %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}}} <-
           Chain.get_transaction(tx_address) do
      {:ok, poi}
    end
  end

  def process(
        {:start_validation, tx = %Transaction{}, welcome_node_public_key, validation_nodes},
        from
      ) when is_binary(welcome_node_public_key) and is_list(validation_nodes) do
        cond do
          !Enum.all?(validation_nodes, &(is_binary(&1))) ->
            {:error,  :invalid_validation_nodes}
          !Enum.all?(validation_nodes ++ [welcome_node_public_key], &Network.node_info(&1)) ->
            {:error, :invalid_validation_nodes}
          true ->
            Validation.start_validation(tx, welcome_node_public_key, validation_nodes)
        end
  end

  def process({:replicate_transaction, tx = %Transaction{validation_stamp: %ValidationStamp{}, cross_validation_stamps: stamps}}, from) when is_list(stamps) and length(stamps) >= 0 do
    validation_node_public_keys = Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce()) |> Enum.map(&(&1.last_public_key))
    if from in validation_node_public_keys do
      Validation.replicate_transaction(tx)
    else
      {:error, :unauthorized}
    end
  end

  def process({:cross_validate, tx_address, stamp = %ValidationStamp{}}, from)
      when is_binary(tx_address) do
    [%Node{last_public_key: coordinator_public_key} | _] = validation_node_public_keys = Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce())
    if coordinator_public_key == from do
      Validation.cross_validate(tx_address, stamp)
    else
      {:error, :unauthorized}
    end
  end

  def process({:cross_validation_done, tx_address, {signature, inconsistencies}}, from)
      when is_binary(tx_address) and is_binary(signature) and is_list(inconsistencies) do
    # [_ | cross_validation_node_public_keys] = Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce()) |> Enum.map(&(&1.last_public_key))
    # f from in cross_validation_node_public_keys do
      Validation.add_cross_validation_stamp(tx_address, {signature, inconsistencies}, from)
    # else
    #  {:error, :unauthorized}
    #end
  end

  def process(msg, from) do
    Logger.info("Node #{from} send an invalid message: #{inspect(msg)}")
    {:error, :invalid_message}
  end
end
