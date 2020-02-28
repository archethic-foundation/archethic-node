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

  ## Examples

     iex> UnirisCrypto.generate_deterministic_keypair("seed", persistence: true)
     iex> <<_public_key::binary-33, _signature::binary-64, encoded_message::binary>> = UnirisP2P.Message.encode(
     ...> {:get_transaction, "DC758E79681F61826C4E57D91A52A9F98C736B918D1AD443EAB2B1C02E5FB900"})
     iex> :erlang.binary_to_term(encoded_message)
     {:get_transaction, "DC758E79681F61826C4E57D91A52A9F98C736B918D1AD443EAB2B1C02E5FB900"} 
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

  ## Examples

     iex> UnirisCrypto.generate_deterministic_keypair("seed", persistence: true)
     iex> encoded_message = UnirisP2P.Message.encode({:get_transaction, "DC758E79681F61826C4E57D91A52A9F98C736B918D1AD443EAB2B1C02E5FB900"})
     iex> {:ok, message, _} = UnirisP2P.Message.decode(encoded_message)
     iex> message
     {:get_transaction, "DC758E79681F61826C4E57D91A52A9F98C736B918D1AD443EAB2B1C02E5FB900"}
  """
  @spec decode(binary()) ::
          {:ok, data :: term(), public_key :: UnirisCrypto.key()} | {:error, :invalid_payload}
  def decode(<<public_key::binary-33, signature::binary-64, binary_payload::binary>>) do
    if Crypto.verify(signature, binary_payload, public_key) do
      payload = :erlang.binary_to_term(binary_payload, [:safe])
      {:ok, payload, public_key}
    else
      {:error, :invalid_payload}
    end
  end

  def decode(_), do: {:error, :invalid_payload}

  @doc """
  Process message coming from a P2P request by actin as a message controller/broker providing an Anti Corruption Layer
  """
  @spec process(message :: tuple(), node_public_key :: UnirisCrypto.key()) ::
          {:ok, term()} | {:error, atom()}
  def process({:get_transaction, tx_address}, _from) when is_binary(tx_address) do
    if Crypto.valid_hash?(tx_address) do
      Chain.get_transaction(tx_address)
    else
      {:error, :invalid_address}
    end
  end

  def process({:get_transaction_chain, tx_address}, _from) when is_binary(tx_address) do
    if UnirisCrypto.valid_hash?(tx_address) do
      Chain.get_transaction_chain(tx_address)
    else
      {:error, :invalid_address}
    end
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
      )
      when is_binary(welcome_node_public_key) and is_list(validation_nodes) do
    cond do
      from != welcome_node_public_key ->
        {:error, :invalid_welcome_node}

      !verify_node_public_key(welcome_node_public_key) ->
        {:error, :invalid_welcome_node}

      !Enum.all?(validation_nodes ++ [welcome_node_public_key], &verify_node_public_key(&1)) ->
        {:error, :invalid_validation_nodes}

      true ->
        Validation.start_validation(tx, welcome_node_public_key, validation_nodes)
    end
  end

  def process(
        {:replicate_transaction,
         tx = %Transaction{validation_stamp: %ValidationStamp{}, cross_validation_stamps: stamps}},
        from
      )
      when is_list(stamps) and length(stamps) >= 0 do
    validation_node_public_keys =
      Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce())
      |> Enum.map(& &1.last_public_key)

    if from in validation_node_public_keys do
      Validation.replicate_transaction(tx)
    else
      {:error, :unauthorized}
    end
  end

  def process({:cross_validate, tx_address, stamp = %ValidationStamp{}}, from)
      when is_binary(tx_address) do
    with true <- Validation.mining?(tx_address),
         tx = %Transaction{} <- Validation.mined_transaction(tx_address),
         [%Node{last_public_key: coordinator_public_key} | _] <-
           Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce()) do
      if coordinator_public_key == from do
        Validation.cross_validate(tx_address, stamp)
      else
        {:error, :unauthorized}
      end
    else
      false ->
        {:error, :invalid_message}
    end
  end

  def process({:cross_validation_done, tx_address, {signature, inconsistencies}}, from)
      when is_binary(tx_address) and is_binary(signature) and is_list(inconsistencies) do
    with true <- Validation.mining?(tx_address),
         tx = %Transaction{} <- Validation.mined_transaction(tx_address),
         [_ | cross_validation_nodes] <-
           Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce()) do
      if from in Enum.map(cross_validation_nodes, & &1.last_public_key) do
        Validation.add_cross_validation_stamp(tx_address, {signature, inconsistencies}, from)
      else
        {:error, :unauthorized}
      end
    else
      false ->
        {:error, :invalid_message}
    end
  end

  def process(msg, from) do
    Logger.info("Node #{from} send an invalid message: #{inspect(msg)}")
    {:error, :invalid_message}
  end

  defp verify_node_public_key(<<public_key::binary-33>>) do
    try do
      Network.node_info(public_key)
    rescue
      CaseClauseError ->
        false
    end
  end

  defp verify_node_public_key(_), do: false
end
