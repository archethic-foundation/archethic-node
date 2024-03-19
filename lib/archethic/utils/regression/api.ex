defmodule Archethic.Utils.Regression.Api do
  @moduledoc """
  Collection of functions to work on the Apis
  """

  require Logger
  alias Archethic.Crypto

  alias Archethic.Utils.WebSocket.Client, as: WSClient

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.TokenLedger.Transfer, as: TokenTransfer
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer, as: UCOTransfer

  alias Archethic.Utils
  alias Archethic.Utils.WebClient

  alias Archethic.Bootstrap.NetworkInit

  @genesis_origin_private_key "01019280BDB84B8F8AEDBA205FE3552689964A5626EE2C60AA10E3BF22A91A036009"
                              |> Base.decode16!()

  @genesis_origin_public_key Application.compile_env!(
                               :archethic,
                               [NetworkInit, :genesis_origin_public_keys]
                             )
                             |> Enum.at(0)

  @faucet_seed Application.compile_env(:archethic, [ArchethicWeb.Explorer.FaucetController, :seed])

  defstruct [
    :host,
    :port,
    protocol: :http
  ]

  @type t() :: %__MODULE__{
          host: String.t(),
          port: integer(),
          protocol: :http | :https
        }

  @doc """
  Send funds to the given seeds
  """
  @spec send_funds_to_seeds(%{String.t() => integer()}, t()) :: String.t()
  def send_funds_to_seeds(amount_by_seed, endpoint) do
    amount_by_address =
      amount_by_seed
      |> Enum.map(fn {seed, amount} ->
        genesis_address =
          Crypto.derive_keypair(seed, 0, :ed25519)
          |> elem(0)
          |> Crypto.derive_address()

        {genesis_address, amount}
      end)
      |> Enum.into(%{})

    send_funds_to_addresses(amount_by_address, endpoint)
  end

  @doc """
  Send funds to the given hexadecimal addresses
  """
  @spec send_funds_to_addresses(%{String.t() => integer()}, t()) :: String.t()
  def send_funds_to_addresses(amount_by_address, endpoint) do
    transfers =
      Enum.map(amount_by_address, fn {address, amount} ->
        Logger.debug("FAUCET: sending #{amount} UCOs to '#{Base.encode16(address)}'")

        %UCOTransfer{
          to: address,
          amount: Utils.to_bigint(amount)
        }
      end)

    {:ok, funding_tx_address} =
      send_transaction_with_await_replication(
        @faucet_seed,
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: transfers
            }
          }
        },
        endpoint
      )

    Logger.debug("FAUCET: transaction address: #{Base.encode16(funding_tx_address)}")
    funding_tx_address
  end

  @doc """
  Send transaction without waiting for validation
  """
  @spec send_transaction(
          String.t(),
          atom(),
          TransactionData.t(),
          t()
        ) :: {:ok, String.t()} | {:error, term()}
  def send_transaction(
        transaction_seed,
        tx_type,
        transaction_data = %TransactionData{},
        endpoint
      ) do
    curve = Crypto.default_curve()
    chain_length = get_chain_size(transaction_seed, curve, endpoint)

    {previous_public_key, previous_private_key} =
      Crypto.derive_keypair(transaction_seed, chain_length, curve)

    {next_public_key, _} = Crypto.derive_keypair(transaction_seed, chain_length + 1, curve)

    genesis_origin_private_key = get_origin_private_key(endpoint)

    tx =
      %Transaction{
        address: Crypto.derive_address(next_public_key),
        type: tx_type,
        data: transaction_data,
        previous_public_key: previous_public_key
      }
      |> Transaction.previous_sign_transaction_with_key(previous_private_key)
      |> Transaction.origin_sign_transaction(genesis_origin_private_key)

    true =
      Crypto.verify?(
        tx.previous_signature,
        Transaction.extract_for_previous_signature(tx) |> Transaction.serialize(:extended),
        tx.previous_public_key
      )

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.json(&1, "/api/transaction", tx_to_json(tx)),
           endpoint.protocol
         ) do
      {:ok, %{"status" => "pending"}} ->
        {:ok, tx.address}

      _ ->
        :error
    end
  end

  @doc """
  Send transaction and wait for validation
  """
  @spec send_transaction_with_await_replication(
          seed :: String.t(),
          type :: atom(),
          data :: TransactionData.t(),
          endpoint :: t(),
          opts :: Keyword.t()
        ) :: {:ok, tx_address :: String.t()} | {:error, reason :: term()}
  def send_transaction_with_await_replication(
        transaction_seed,
        tx_type,
        transaction_data = %TransactionData{},
        endpoint,
        opts \\ []
      ) do
    curve = Crypto.default_curve()
    chain_length = get_chain_size(transaction_seed, curve, endpoint)

    {previous_public_key, previous_private_key} =
      Crypto.derive_keypair(transaction_seed, chain_length, curve)

    {next_public_key, _} = Crypto.derive_keypair(transaction_seed, chain_length + 1, curve)

    genesis_origin_private_key = get_origin_private_key(endpoint)

    tx =
      %Transaction{
        address: Crypto.derive_address(next_public_key),
        type: tx_type,
        data: transaction_data,
        previous_public_key: previous_public_key
      }
      |> Transaction.previous_sign_transaction_with_key(previous_private_key)
      |> Transaction.origin_sign_transaction(genesis_origin_private_key)

    true =
      Crypto.verify?(
        tx.previous_signature,
        Transaction.extract_for_previous_signature(tx) |> Transaction.serialize(:extended),
        tx.previous_public_key
      )

    replication_attestation = Task.async(fn -> await_replication(tx.address) end)

    Process.sleep(100)

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.json(&1, "/api/transaction", tx_to_json(tx)),
           endpoint.protocol
         ) do
      {:ok, %{"status" => "pending"}} ->
        await_timeout = Keyword.get(opts, :await_timeout, 5000)

        case Task.yield(replication_attestation, await_timeout) ||
               Task.shutdown(replication_attestation) do
          {:ok, :ok} ->
            {:ok, tx.address}

          {:ok, {:error, reason}} ->
            Logger.error(
              "Transaction #{Base.encode16(tx.address)}confirmation fails - #{inspect(reason)}"
            )

            {:error, reason}

          nil ->
            Logger.error("Transaction #{Base.encode16(tx.address)} validation timeouts")
            {:error, :timeout}
        end

      {:ok, %{"status" => "invalid", "errors" => errors}} ->
        {:error, errors}

      {:error, reason} ->
        Logger.error(
          "Transaction #{Base.encode16(tx.address)} submission fails - #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Get the current nonce public key
  """
  @spec get_storage_nonce_public_key(t()) :: String.t()
  def get_storage_nonce_public_key(endpoint) do
    query = ~s|query {sharedSecrets { storageNoncePublicKey}}|

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.query(&1, query),
           endpoint.protocol
         ) do
      {:ok,
       %{
         "data" => %{
           "sharedSecrets" => %{"storageNoncePublicKey" => storage_nonce_public_key}
         }
       }} ->
        Base.decode16!(storage_nonce_public_key)
    end
  end

  @doc """
  Get the transaction chain's size
  """
  @spec get_chain_size(String.t(), atom(), t()) :: integer()
  def get_chain_size(seed, curve, endpoint) do
    genesis_address =
      seed
      |> Crypto.derive_keypair(0, curve)
      |> elem(0)
      |> Crypto.derive_address()

    query =
      ~s|query {last_transaction(address: "#{Base.encode16(genesis_address)}"){ chainLength }}|

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.query(&1, query),
           endpoint.protocol
         ) do
      {:ok, %{"errors" => [%{"message" => "transaction_not_exists"}]}} ->
        0

      {:ok, %{"data" => %{"last_transaction" => %{"chainLength" => chain_length}}}} ->
        chain_length

      {:error, error_info} ->
        raise "chain size failed #{inspect(error_info)}"
    end
  end

  @doc """
  Get the last transaction of the chain
  """
  @spec get_last_transaction(binary(), t()) :: map()
  def get_last_transaction(address, endpoint) do
    query = ~s"""
      query {
        lastTransaction(address: "#{Base.encode16(address)}"){
          type
          address
          data {
            content
            code
          }
          validationStamp{
            timestamp
          }
        }
      }
    """

    {:ok, %{"data" => %{"lastTransaction" => transaction}}} =
      WebClient.with_connection(
        endpoint.host,
        endpoint.port,
        &WebClient.query(&1, query),
        endpoint.protocol
      )

    transaction
  end

  @doc """
  Get the UCO balance of the chain
  """
  @spec get_uco_balance(binary(), t()) :: integer()
  def get_uco_balance(address, endpoint) do
    query = ~s|query {lastTransaction(address: "#{Base.encode16(address)}"){ balance { uco }}}|

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.query(&1, query),
           endpoint.protocol
         ) do
      {:ok, %{"data" => %{"lastTransaction" => %{"balance" => %{"uco" => uco}}}}} ->
        uco

      {:ok, %{"errors" => [%{"message" => "transaction_not_exists"}]}} ->
        balance_query = ~s| query { balance(address: "#{Base.encode16(address)}") { uco } } |

        {:ok,
         %{
           "data" => %{
             "balance" => %{
               "uco" => uco
             }
           }
         }} =
          WebClient.with_connection(
            endpoint.host,
            endpoint.port,
            &WebClient.query(&1, balance_query),
            endpoint.protocol
          )

        uco
    end
  end

  @doc """
  Get the inputs of transaction
  """
  @spec get_inputs(binary(), t()) :: map()
  def get_inputs(address, endpoint) do
    query = ~s"""
      query {
        transactionInputs(address: "#{Base.encode16(address)}"){
          amount
          type
          from
          timestamp
        }
      }
    """

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.query(&1, query),
           endpoint.protocol
         ) do
      {:ok, %{"data" => %{"transactionInputs" => inputs}}} ->
        inputs
    end
  end

  # ------ PRIVATE ---------

  defp await_replication(txn_address) do
    query = """
    subscription {
    transactionConfirmed(address: "#{Base.encode16(txn_address)}") {
      nbConfirmations
    }
    }
    """

    WSClient.absinthe_sub(
      query,
      _var = %{},
      _sub_id = Base.encode16(txn_address)
    )

    query = """
    subscription {
      transactionError(address: "#{Base.encode16(txn_address)}") {
        reason
    }
    }
    """

    WSClient.absinthe_sub(
      query,
      _var = %{},
      _sub_id = Base.encode16(txn_address)
    )

    receive do
      %{"transactionConfirmed" => %{"nbConfirmations" => _}} ->
        :ok

      %{"transactionError" => %{"reason" => reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_transaction_fee(
        transaction_seed,
        tx_type,
        transaction_data = %TransactionData{},
        endpoint
      ) do
    curve = Crypto.default_curve()
    chain_length = get_chain_size(transaction_seed, curve, endpoint)

    {previous_public_key, previous_private_key} =
      Crypto.derive_keypair(transaction_seed, chain_length, curve)

    {next_public_key, _} = Crypto.derive_keypair(transaction_seed, chain_length + 1, curve)

    genesis_origin_private_key = get_origin_private_key(endpoint)

    tx =
      %Transaction{
        address: Crypto.derive_address(next_public_key),
        type: tx_type,
        data: transaction_data,
        previous_public_key: previous_public_key
      }
      |> Transaction.previous_sign_transaction_with_key(previous_private_key)
      |> Transaction.origin_sign_transaction(genesis_origin_private_key)

    true =
      Crypto.verify?(
        tx.previous_signature,
        Transaction.extract_for_previous_signature(tx) |> Transaction.serialize(:extended),
        tx.previous_public_key
      )

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.json(&1, "/api/transaction_fee", tx_to_json(tx)),
           endpoint.protocol
         ) do
      {:ok, _transaction_fee} = transaction_fee ->
        transaction_fee

      error ->
        error
    end
  end

  defp get_origin_private_key(endpoint) do
    body = %{
      "origin_public_key" => Base.encode16(@genesis_origin_public_key)
    }

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.json(&1, "/api/origin_key", body),
           endpoint.protocol
         ) do
      {:ok,
       %{
         "encrypted_origin_private_keys" => encrypted_origin_private_keys,
         "encrypted_secret_key" => encrypted_secret_key
       }} ->
        aes_key =
          Base.decode16!(encrypted_secret_key, case: :mixed)
          |> Crypto.ec_decrypt!(@genesis_origin_private_key)

        Base.decode16!(encrypted_origin_private_keys, case: :mixed)
        |> Crypto.aes_decrypt!(aes_key)

      _ ->
        @genesis_origin_private_key
    end
  end

  defp tx_to_json(%Transaction{
         version: version,
         address: address,
         type: type,
         data: %TransactionData{
           ledger: %Ledger{
             uco: %UCOLedger{transfers: uco_transfers},
             token: %TokenLedger{transfers: token_transfers}
           },
           code: code,
           content: content,
           recipients: recipients,
           ownerships: ownerships
         },
         previous_public_key: previous_public_key,
         previous_signature: previous_signature,
         origin_signature: origin_signature
       }) do
    %{
      "version" => version,
      "address" => Base.encode16(address),
      "type" => Atom.to_string(type),
      "previousPublicKey" => Base.encode16(previous_public_key),
      "previousSignature" => Base.encode16(previous_signature),
      "originSignature" => Base.encode16(origin_signature),
      "data" => %{
        "ledger" => %{
          "uco" => %{
            "transfers" =>
              Enum.map(uco_transfers, fn %UCOTransfer{to: to, amount: amount} ->
                %{"to" => Base.encode16(to), "amount" => amount}
              end)
          },
          "token" => %{
            "transfers" =>
              Enum.map(token_transfers, fn %TokenTransfer{
                                             to: to,
                                             amount: amount,
                                             token_address: token_address,
                                             token_id: token_id
                                           } ->
                %{
                  "to" => Base.encode16(to),
                  "amount" => amount,
                  "tokenAddress" => Base.encode16(token_address),
                  "tokenId" => token_id
                }
              end)
          }
        },
        "code" => code,
        "content" => Base.encode16(content),
        "recipients" =>
          Enum.map(recipients, fn %Recipient{address: address, action: action, args: args} ->
            %{"address" => Base.encode16(address), "action" => action, "args" => args}
          end),
        "ownerships" =>
          Enum.map(ownerships, fn %Ownership{
                                    secret: secret,
                                    authorized_keys: authorized_keys
                                  } ->
            %{
              "secret" => Base.encode16(secret),
              "authorizedKeys" =>
                Enum.map(authorized_keys, fn {public_key, encrypted_secret_key} ->
                  %{
                    "publicKey" => Base.encode16(public_key),
                    "encryptedSecretKey" => Base.encode16(encrypted_secret_key)
                  }
                end)
            }
          end)
      }
    }
  end

  def get_unspent_outputs(address, endpoint) do
    query = ~s"""
      query {
        chainUnspentOutputs(address: "#{Base.encode16(address)}"){
          amount
          type
          from
          timestamp
          state
          tokenAddress
          tokenId
        }
      }
    """

    case WebClient.with_connection(
           endpoint.host,
           endpoint.port,
           &WebClient.query(&1, query),
           endpoint.protocol
         ) do
      {:ok, %{"data" => %{"chainUnspentOutputs" => unspent_outputs}}} ->
        unspent_outputs
    end
  end
end
