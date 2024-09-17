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

  @spec request(req :: WasmIO.Request.t()) :: Result.t()
  def request(%{"method" => "getBalance", "params" => %{"hex" => address}}) do
    address
    |> Base.decode16!(case: :mixed)
    |> Archethic.get_balance()
    |> transform_balance()
    |> Result.wrap_ok()
  end

  def request(%{"method" => "getGenesisAddress", "params" => %{"hex" => address}}) do
    address
    |> Base.decode16!(case: :mixed)
    |> Library.Common.Chain.get_genesis_address()
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("network issue")
  end

  def request(%{"method" => "getFirstTransactionAddress", "params" => %{"hex" => address}}) do
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

  def request(%{"method" => "getLastAddress", "params" => %{"hex" => address}}) do
    Library.Common.Chain.get_last_address(address)
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("not found")
  end

  def request(%{"method" => "getPreviousAddress", "params" => %{"hex" => previous_public_key}}) do
    previous_public_key
    |> String.upcase()
    |> Library.Common.Chain.get_previous_address()
    |> transform_hex()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("invalid previous public key")
  end

  def request(%{"method" => "getGenesisPublicKey", "params" => %{"hex" => public_key}}) do
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

  def request(%{"method" => "getTransaction", "params" => %{"hex" => address}}) do
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

  def request(%{"method" => "getLastTransaction", "params" => %{"hex" => address}}) do
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
  def request(%{
        "method" => "callFunction",
        "params" => %{
          "address" => %{"hex" => address},
          "functionName" => function_name,
          "args" => args
        }
      }) do
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
  def request(%{
        "method" => "hmacWithStorageNonce",
        "params" => %{
          "data" => data,
          "hashFunction" => hash_function
        }
      }) do
    case Process.get(:contract_seed) do
      nil ->
        Result.wrap_error("Missing contract seed")

      contract_seed ->
        key = :crypto.hash(:sha256, Crypto.storage_nonce() <> contract_seed)

        hash_function =
          case hash_function do
            "sha256" ->
              :sha256

            "sha512" ->
              :sha512

            "sha3_256" ->
              :sha3_256

            "sha3_512" ->
              :sha3_512

            _ ->
              # TODO: KECCAK256
              # TODO: BLAKE2B
              nil
          end

        if hash_function == nil do
          Result.wrap_error("Invalid hash function")
        else
          :crypto.mac(:hmac, hash_function, key, data |> Base.decode16!()) |> Base.encode16()
        end
    end
  end

  def request(%{
        "method" => "signWithRecovery",
        "params" => data
      }) do
    data
    # |> Base.decode16!(case: :mixed)
    |> Library.Common.Crypto.sign_with_recovery()
    |> Result.wrap_ok()
  end

  def request(%{
        "method" => "decryptWithStorageNonce",
        "params" => data
      }) do
    data
    |> Base.decode16!(case: :mixed)
    |> Library.Common.Crypto.decrypt_with_storage_nonce()
    |> Result.wrap_ok()
  rescue
    _ -> Result.wrap_error("decryption failed")
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
