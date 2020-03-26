defmodule UnirisSync.TransactionLoader do
  @moduledoc false

  alias UnirisChain, as: Chain
  alias UnirisChain.Transaction
  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto
  alias UnirisSharedSecrets, as: SharedSecrets
  alias UnirisPubSub, as: PubSub

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_) do
    PubSub.register_to_new_transaction()
    {:ok, [], {:continue, :load_transactions}}
  end

  def handle_continue(:load_transactions, state) do
    Logger.info("Load transactions...")
    Enum.map(Chain.node_transactions(), &load_transaction/1)

    case Chain.get_last_node_shared_secrets_transaction() do
      {:ok, tx} ->
        load_transaction(tx)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, state) do
    load_transaction(tx)
    {:noreply, state}
  end

  def handle_info({:new_transaction, _}, state) do
    {:noreply, state}
  end

  defp load_transaction(%Transaction{type: :node, data: %{content: content}}) do
    node = extract_node_from_content(content)
    P2P.add_node(node)
    Logger.info("New node added #{Base.encode16(node.first_public_key)}")
    if Crypto.node_public_key() != node.last_public_key do
      P2P.connect_node(node)
    end
  end

  defp load_transaction(%Transaction{
        type: :node_shared_secrets,
        data: %{keys: %{authorized_keys: auth_keys, secret: secret}}
      }) do
    Enum.each(auth_keys, fn {key, enc_key} ->
      Node.authorize(key)
      Logger.info("Node #{Base.encode16(key)} authorized")

      if key == Crypto.node_public_key() do
        aes_key = Crypto.ec_decrypt_with_node_key!(enc_key)

        %{
          daily_nonce_seed: daily_nonce_seed,
          storage_nonce_seed: storage_nonce_seed,
          origin_keys_seeds: origin_keys_seeds
        } = Crypto.aes_decrypt!(secret, aes_key)

        Crypto.set_daily_nonce(daily_nonce_seed)
        Logger.info("Daily nonce updated")

        Crypto.set_storage_nonce(storage_nonce_seed)
        Logger.info("Storage nonce updated")

        Enum.each(origin_keys_seeds, fn seed ->
          {pub, _} = Crypto.generate_deterministic_keypair(seed)
          SharedSecrets.add_origin_public_key(:software, pub)
          Logger.info("Origin public key #{Base.encode16(pub)} added")
        end)
      end
    end)
  end

  defp load_transaction(tx = %Transaction{data: %{code: contract_code}}) when contract_code != "" do
    UnirisInterpreter.new_contract(tx)
  end

  defp load_transaction(_) do
    :ok
  end

  defp extract_node_from_content(content) do
    [ip_match, port_match, first_public_key_match, last_public_key_match] =
      Regex.scan(~r/(?<=ip|port|first_public_key|last_public_key).*/, content)

    {:ok, ip} =
      ip_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> String.to_charlist()
      |> :inet.parse_address()

    port =
      port_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> String.to_integer()

    first_public_key =
      first_public_key_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> Base.decode16!()

    last_public_key =
      last_public_key_match
      |> List.first()
      |> String.replace(":", "")
      |> String.trim()
      |> Base.decode16!()

    %Node{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: last_public_key
    }
  end
end
