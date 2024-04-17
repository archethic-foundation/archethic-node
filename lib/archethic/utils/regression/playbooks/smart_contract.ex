defmodule Archethic.Utils.Regression.Playbook.SmartContract do
  @moduledoc """
  Play and verify smart contracts.
  """

  use Archethic.Utils.Regression.Playbook
  use Retry

  alias Archethic.Crypto

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.WebSocket.Client, as: WSClient

  # alias __MODULE__.Counter
  # alias __MODULE__.Legacy
  # alias __MODULE__.UcoAth
  # alias __MODULE__.DeterministicBalance
  # alias __MODULE__.Dex
  alias __MODULE__.Throw

  require Logger

  def play!(nodes, opts) do
    # TODO: add a debug opts (default: false)
    #       false: no logs + parallel execution
    #       true: logs + sequential execution

    Crypto.Ed25519.LibSodiumPort.start_link()

    Logger.info("Play smart contract transactions on #{inspect(nodes)} with #{inspect(opts)}")
    port = Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]
    host = :lists.nth(:rand.uniform(length(nodes)), nodes)

    endpoint = %Api{host: host, port: port, protocol: :http}
    Logger.info("Using endpoint: #{inspect(endpoint)}")

    WSClient.start_link(host: host, port: port)
    storage_nonce_pubkey = Api.get_storage_nonce_public_key(endpoint)

    res = [
      # {"DeterministicBalance", DeterministicBalance.play(storage_nonce_pubkey, endpoint)},
      # {"Counter", Counter.play(storage_nonce_pubkey, endpoint)},
      # {"Legacy", Legacy.play(storage_nonce_pubkey, endpoint)},
      # {"Dex", Dex.play(storage_nonce_pubkey, endpoint)},
      {"Throw", Throw.play(storage_nonce_pubkey, endpoint)}
      # {"UcoAth", UcoAth.play(storage_nonce_pubkey, endpoint)}
    ]

    Enum.each(res, fn
      {name, :error} -> Logger.error("#{name} failed")
      _ -> :ok
    end)
  end

  @doc """
  Deploy a smart contract
  """
  @spec deploy(String.t(), TransactionData.t(), binary(), Api.t()) :: binary()
  def deploy(seed, data, storage_nonce_pubkey, endpoint) do
    Logger.debug("DEPLOY: Deploying contract")

    secret_key = :crypto.strong_rand_bytes(32)

    # add the ownerships required for smart contract
    data = %TransactionData{
      data
      | ownerships: [
          %Ownership{
            secret: Crypto.aes_encrypt(seed, secret_key),
            authorized_keys: %{
              storage_nonce_pubkey => Crypto.ec_encrypt(secret_key, storage_nonce_pubkey)
            }
          }
          | data.ownerships
        ]
    }

    {:ok, address} =
      Api.send_transaction_with_await_replication(
        seed,
        :contract,
        data,
        endpoint
      )

    Logger.debug("DEPLOY: Deployed at #{Base.encode16(address)}")

    address
  end

  @doc """
  Trigger a smart contract by sending a transaction from given seed
  By passing the [wait: true] flag, it will block until the contract produces a new transaction
  """
  @spec trigger(
          trigger_seed :: String.t(),
          contract_address :: Crypto.prepended_hash(),
          endpoint :: Api.t(),
          opts :: Keyword.t()
        ) :: {:ok, tx_address :: Crypto.prepended_hash()} | {:error, reason :: term()}
  def trigger(trigger_seed, contract_address, endpoint, opts \\ []) do
    Logger.debug("TRIGGER: Sending trigger transaction")
    wait? = Keyword.get(opts, :wait, false)

    last_contract_address =
      if wait? do
        contract_address
        |> Api.get_last_transaction(endpoint)
        |> Map.get("address")
        |> Base.decode16!()
      else
        nil
      end

    res =
      Api.send_transaction_with_await_replication(
        trigger_seed,
        Keyword.get(opts, :type, :transfer),
        %TransactionData{
          content: Keyword.get(opts, :content, ""),
          ledger: Keyword.get(opts, :ledger, %Ledger{}),
          recipients: Keyword.get(opts, :recipients, [%Recipient{address: contract_address}])
        },
        endpoint,
        opts
      )

    case res do
      {:ok, trigger_address} ->
        Logger.debug("TRIGGER: transaction sent at #{Base.encode16(trigger_address)}")

        if Keyword.get(opts, :wait, false) do
          # wait until the contract produces a new transaction
          :ok = wait_until_new_transaction(last_contract_address, endpoint)
        end

      {:error, reason} ->
        Logger.debug("TRIGGER: transaction failed with reason: #{inspect(reason)}")
    end

    res
  end

  @doc """
  Call the API to execute a public function
  """
  @spec call_function(
          contract_address :: Crypto.prepended_hash(),
          function_name :: String.t(),
          args :: list(),
          resolve_last :: boolean(),
          endpoint :: Api.t()
        ) :: {:ok, result :: term()} | {:error, error :: term()}
  defdelegate call_function(contract_address, function_name, args, resolve_last, endpoint),
    to: Api

  def random_address() do
    <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
  end

  def random_seed() do
    :crypto.strong_rand_bytes(10)
  end

  defp wait_until_new_transaction(address, endpoint) do
    address_hex = Base.encode16(address)

    # retry every 500ms until 20 retries
    retry with: constant_backoff(500) |> Stream.take(20) do
      %{"address" => last_address_hex} = Api.get_last_transaction(address, endpoint)

      if last_address_hex == address_hex do
        :error
      else
        :ok
      end
    after
      _ ->
        Logger.debug("TRIGGER: contract produced a new transaction")
        :ok
    else
      _ ->
        Logger.error("TRIGGER: TIMEOUT: contract did not produce a new transaction in time")
        :error
    end
  end

  def await_no_more_calls(contract_address, endpoint) do
    call_utxos =
      contract_address
      |> Api.get_unspent_outputs(endpoint)
      |> Enum.filter(&(Map.get(&1, "type") == "call"))

    case call_utxos do
      [] ->
        :ok

      calls ->
        Logger.debug("Remaining calls #{length(calls)}")
        Process.sleep(200)
        await_no_more_calls(contract_address, endpoint)
    end
  end
end
