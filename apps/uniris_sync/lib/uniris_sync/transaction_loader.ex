defmodule UnirisSync.TransactionLoader do
  @moduledoc false

  use GenServer

  alias UnirisChain.Transaction
  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, []}
  end

  def handle_call(:preload_transactions, _from, state) do
    Logger.info("Preloading transactions...")
    transactions = UnirisChain.list_transactions()

    transactions
    |> Enum.filter(&(&1.type == :node))
    |> Enum.each(&handle_transaction/1)

    transactions
    |> Enum.filter(&(&1.type == :node_shared_secrets))
    |> Enum.sort_by(&(&1.timestamp))
    |> case do
      [tx | _] ->
        handle_transaction(tx)
      _ ->
        :ok
    end

    transactions
    |> Enum.reject(&(&1.type in [:node, :node_shared_secrets]))
    |> Enum.each(&handle_transaction/1)

    {:reply, :ok, state}
  end

  def handle_cast({:new_transaction, tx = %Transaction{}}, state) do
    handle_transaction(tx)
    {:noreply, state}
  end

  defp handle_transaction(%Transaction{type: :node, data: %{content: content}}) do
    node = extract_node_from_content(content)
    :ok = P2P.add_node(node)
    :ok = P2P.connect_node(node)
    Logger.info("New node registered")
  end

  defp handle_transaction(
         %Transaction{
           type: :node_shared_secrets,
           data: %{keys: %{secret: secret, authorized_keys: auth_keys}}
         }
      ) do
    Enum.each(auth_keys, fn {key, enc_key} ->
      Node.authorize(key)
      Logger.info("Node #{Base.encode16(key)} authorized")

      if key == Crypto.node_public_key() do
        # Renew shared key
        aes_key = Crypto.ec_decrypt_with_node_key!(enc_key)
        %{daily_nonce_seed: daily_nonce_seed} = Crypto.aes_decrypt!(secret, aes_key)
        Crypto.set_daily_nonce(daily_nonce_seed)
        Logger.info("Node shared key updated")
      end
    end)
  end

  defp handle_transaction(tx = %Transaction{data: %Transaction.Data{code: code}}) do
    if code == "" do
      :ok
    else
      UnirisInterpreter.new_contract(tx)
    end
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

  def new_transaction(tx = %Transaction{}) do
    GenServer.cast(__MODULE__, {:new_transaction, tx})
  end

  def preload_transactions() do
    GenServer.call(__MODULE__, :preload_transactions)
  end
end
