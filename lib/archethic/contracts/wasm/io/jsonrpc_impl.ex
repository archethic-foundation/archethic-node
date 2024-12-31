defmodule Archethic.Contracts.Wasm.IO.JSONRPCImpl do
  @moduledoc """
  Implementation of IO functions via JSONRPC serialization
  """
  alias Archethic.Contracts.Wasm.IO, as: WasmIO
  alias Archethic.Contracts.Wasm.Result
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction

  #########################################################
  # CHAIN
  #########################################################

  @spec request(req :: WasmIO.Request.t(), opts :: Keyword.t()) :: Result.t()
  def request(%{"method" => "getBalance", "params" => %{"hex" => address}}, _opts) do
    address
    |> Base.decode16!(case: :mixed)
    |> Archethic.get_balance()
    |> transform_balance()
    |> Result.wrap_ok()
  end

  def request(%{"method" => "getGenesisAddress", "params" => %{"hex" => address}}, _opts) do
    address
    |> Base.decode16!(case: :mixed)
    |> Library.Common.Chain.get_genesis_address()
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("network issue")
  end

  def request(%{"method" => "getFirstTransactionAddress", "params" => %{"hex" => address}}, _opts) do
    case address
         |> Base.decode16!(case: :mixed)
         |> Library.Common.Chain.get_first_transaction_address() do
      nil ->
        Result.wrap_error("not found")

      first_address ->
        first_address
        |> transform_hex()
        |> Result.wrap_ok()
    end
  end

  def request(%{"method" => "getLastAddress", "params" => %{"hex" => address}}, _opts) do
    Library.Common.Chain.get_last_address(address)
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("not found")
  end

  def request(
        %{"method" => "getPreviousAddress", "params" => %{"hex" => previous_public_key}},
        _opts
      ) do
    previous_public_key
    |> String.upcase()
    |> Library.Common.Chain.get_previous_address()
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("invalid previous public key")
  end

  def request(%{"method" => "getGenesisPublicKey", "params" => %{"hex" => public_key}}, _opts) do
    case public_key
         |> Base.decode16!(case: :mixed)
         |> Library.Common.Chain.get_genesis_public_key() do
      nil ->
        Result.wrap_error("not found")

      genesis_public_key ->
        genesis_public_key
        |> transform_hex()
        |> Result.wrap_ok()
    end
  end

  def request(%{"method" => "getTransaction", "params" => %{"hex" => address}}, _opts) do
    case address
         |> Base.decode16!(case: :mixed)
         |> Archethic.search_transaction() do
      {:ok, tx} ->
        tx
        |> transform_transaction()
        |> Result.wrap_ok()

      _ ->
        Result.wrap_error("not found")
    end
  end

  def request(%{"method" => "getLastTransaction", "params" => %{"hex" => address}}, _opts) do
    case address
         |> Base.decode16!(case: :mixed)
         |> Archethic.get_last_transaction() do
      {:ok, tx} ->
        tx
        |> transform_transaction()
        |> Result.wrap_ok()

      _ ->
        Result.wrap_error("not found")
    end
  end

  #########################################################
  # CONTRACT
  #########################################################
  def request(
        %{
          "method" => "callFunction",
          "params" => %{
            "address" => %{"hex" => address},
            "functionName" => function_name,
            "args" => args
          }
        },
        _opts
      ) do
    args =
      if args == nil do
        []
      else
        args
      end

    address
    |> Base.decode16!(case: :mixed)
    |> Library.Common.Contract.call_function(function_name, args)
    |> Result.wrap_ok()
  rescue
    e in Library.Error ->
      Result.wrap_error(e.message)
  end

  #########################################################
  # CRYPTO
  #########################################################
  def request(
        %{
          "method" => "hmacWithStorageNonce",
          "params" => %{
            "data" => %{"hex" => data},
            "hashFunction" => hash_function
          }
        },
        opts
      ) do
    case Keyword.get(opts, :encrypted_contract_seed) do
      nil ->
        Result.wrap_error("Missing contract seed")

      {encrypted_seed, encrypted_key} ->
        with {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
             {:ok, seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
          key = :crypto.hash(:sha256, Crypto.storage_nonce() <> seed)

          # TODO: KECCAK256
          # TODO: BLAKE2B
          case [{0, :sha256}, {1, :sha512}, {2, :sha3_256}, {3, :sha3_512}]
               |> Map.new()
               |> Map.get(hash_function) do
            nil ->
              Result.wrap_error("Invalid hash function")

            _ ->
              :crypto.mac(:hmac, hash_function, key, data |> Base.decode16!())
              |> transform_hex()
              |> Result.wrap_ok()
          end
        else
          _ -> Result.wrap_error("Unable to decrypt seed for hmacWithStorageNonce")
        end
    end
  end

  def request(
        %{
          "method" => "signWithRecovery",
          "params" => %{"hex" => data}
        },
        opts
      ) do
    case Keyword.get(opts, :encrypted_contract_seed) do
      nil ->
        Result.wrap_error("Missing contract seed")

      {encrypted_seed, encrypted_key} ->
        with {:ok, aes_key} <- Crypto.ec_decrypt_with_storage_nonce(encrypted_key),
             {:ok, seed} <- Crypto.aes_decrypt(encrypted_seed, aes_key) do
          data = Base.decode16!(data, case: :mixed)

          {_pub, <<_::16, priv::binary>>} = Crypto.derive_keypair(seed, 0, :secp256k1)

          case ExSecp256k1.sign(data, priv) do
            {:ok, {r, s, v}} ->
              Result.wrap_ok(%{
                "r" => transform_hex(r),
                "s" => transform_hex(s),
                "v" => v
              })

            {:error, err} ->
              err |> inspect() |> Result.wrap_error()
          end
        else
          _ -> Result.wrap_error("Unable to decrypt seed for signWithRecovery")
        end
    end
  end

  def request(
        %{
          "method" => "decryptWithStorageNonce",
          "params" => %{"hex" => data}
        },
        _opts
      ) do
    data
    |> Base.decode16!(case: :mixed)
    |> Library.Common.Crypto.decrypt_with_storage_nonce()
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ -> Result.wrap_error("decryption failed")
  end

  #########################################################
  # HTTP
  #########################################################
  def request(
        %{
          "method" => "request",
          "params" => %{
            "body" => body,
            "headers" => headers,
            "method" => method,
            "uri" => uri
          }
        },
        _opts
      ) do
    method =
      case method do
        0 -> "GET"
        1 -> "PUT"
        2 -> "POST"
        3 -> "PATCH"
        4 -> "DELETE"
      end

    headers =
      Enum.reduce(headers, %{}, fn %{"key" => key, "value" => value}, acc ->
        Map.put(acc, key, value)
      end)

    Library.Common.Http.request(uri, method, headers, body, true)
    |> Result.wrap_ok()
  rescue
    e in Library.Error ->
      Result.wrap_error(e.message)
  end

  def request(
        %{
          "method" => "requestMany",
          "params" => reqs
        },
        _opts
      ) do
    reqs =
      Enum.map(reqs, fn %{
                          "body" => body,
                          "headers" => headers,
                          "method" => method,
                          "uri" => uri
                        } ->
        method =
          case method do
            0 -> "GET"
            1 -> "PUT"
            2 -> "POST"
            3 -> "PATCH"
            4 -> "DELETE"
          end

        headers =
          Enum.reduce(headers, %{}, fn %{"key" => key, "value" => value}, acc ->
            Map.put(acc, key, value)
          end)

        %{
          "body" => body,
          "headers" => headers,
          "method" => method,
          "url" => uri
        }
      end)

    Library.Common.Http.request_many(reqs, true)
    |> Result.wrap_ok()
  rescue
    e in Library.Error ->
      Result.wrap_error(e.message)
  end

  defp transform_balance(%{uco: uco, token: token}) do
    %{
      "uco" => uco,
      "token" =>
        Enum.map(token, fn {{address, token_id}, amount} ->
          %{
            "tokenAddress" => transform_hex(address),
            "tokenId" => token_id,
            "amount" => amount
          }
        end)
    }
  end

  # todo: lots of fields missing
  defp transform_transaction(%Transaction{type: type, data: data}) do
    %{
      "type" => type,
      "data" => %{
        "content" => data.content,
        "code" => data.code,
        "ledger" => %{
          "uco" => %{
            "transfers" =>
              Enum.map(data.ledger.uco.transfers, fn t ->
                %{
                  "to" => transform_hex(t.to),
                  "amount" => t.amount
                }
              end)
          },
          "token" => %{
            "transfers" =>
              Enum.map(data.ledger.token.transfers, fn t ->
                %{
                  "to" => transform_hex(t.to),
                  "amount" => t.amount,
                  "tokenAddress" => transform_hex(t.token_address),
                  "tokenId" => t.token_id
                }
              end)
          }
        }
      }
    }
  end

  # the hex "struct" used by the smart contract language to represent Address, PublicKey etc.
  defp transform_hex(bin) do
    # because library functions returns hex directly
    if String.printable?(bin) && String.match?(bin, ~r/^[[:xdigit:]]+$/) do
      %{"hex" => bin}
    else
      %{"hex" => bin |> Base.encode16()}
    end
  end
end
