defmodule Archethic.Contracts.Wasm.IO.JSONRPCImpl do
  @moduledoc """
  Implementation of IO functions via JSONRPC serialization
  """
  alias Archethic.Contracts.Wasm.IO, as: WasmIO
  alias Archethic.Contracts.Wasm.Result
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.TransactionChain.Transaction

  #########################################################
  # CHAIN
  #########################################################

  @spec request(req :: WasmIO.Request.t()) :: Result.t()
  def request(%{method: "getBalance", params: address}) do
    address
    |> Base.decode16!()
    |> Archethic.get_balance()
    |> transform_balance()
    |> Result.wrap_ok()
  end

  def request(%{method: "getGenesisAddress", params: address}) do
    address
    |> Base.decode16!()
    |> Library.Common.Chain.get_genesis_address()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("network issue")
  end

  def request(%{method: "getFirstTransactionAddress", params: address}) do
    case address
         |> Base.decode16!()
         |> Library.Common.Chain.get_first_transaction_address() do
      nil ->
        Result.wrap_error("not found")

      first_address ->
        Result.wrap_ok(first_address)
    end
  end

  def request(%{method: "getLastAddress", params: address}) do
    Library.Common.Chain.get_last_address(address)
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("not found")
  end

  def request(%{method: "getPreviousAddress", params: previous_public_key}) do
    previous_public_key
    |> Base.decode16!()
    |> Library.Common.Chain.get_previous_address()
    |> Result.wrap_ok()
  rescue
    _ ->
      Result.wrap_error("invalid previous public key")
  end

  def request(%{method: "getGenesisPublicKey", params: public_key}) do
    case public_key
         |> Base.decode16!()
         |> Library.Common.Chain.get_genesis_public_key() do
      nil -> Result.wrap_error("not found")
      genesis_public_key -> Result.wrap_ok(genesis_public_key)
    end
  end

  def request(%{method: "getTransaction", params: address}) do
    case address
         |> Base.decode16!()
         |> Library.Common.Chain.get_transaction() do
      nil ->
        Result.wrap_error("not found")

      tx ->
        tx
        |> transform_transaction()
        |> Result.wrap_ok()
    end
  end

  def request(%{method: "getLastTransaction", params: address}) do
    case address
         |> Base.decode16!()
         |> Library.Common.Chain.get_last_transaction() do
      nil ->
        Result.wrap_error("not found")

      tx ->
        tx
        |> transform_transaction()
        |> Result.wrap_ok()
    end
  end

  #########################################################
  # CONTRACT
  #########################################################
  def request(%{
        method: "callFunction",
        params: %{
          "address" => address,
          "functionName" => function_name,
          "args" => args
        }
      }) do
    address
    |> Base.decode16!()
    |> Library.Common.Contract.call_function(function_name, args)
    |> Result.wrap_ok()
  rescue
    _ -> Result.wrap_error("uh oh")
  end

  #########################################################
  # CRYPTO
  #########################################################
  def request(%{
        method: "hmacWithStorageNonce",
        params: %{
          "data" => data,
          "hashFunction" => hash_function
        }
      }) do
    data
    |> Base.decode16!()
    |> Library.Common.Crypto.hmac(hash_function, "")
    |> Result.wrap_ok()
  rescue
    _ -> Result.wrap_error("uh oh")
  end

  def request(%{
        method: "signWithRecovery",
        params: data
      }) do
    data
    # |> Base.decode16!()
    |> Library.Common.Crypto.sign_with_recovery()
    |> Result.wrap_ok()
  end

  def request(%{
        method: "decryptWithStorageNonce",
        params: data
      }) do
    data
    |> Base.decode16!()
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
          %{"tokenAddress" => address, "tokenId" => token_id, "amount" => amount}
        end)
    }
  end

  defp transform_transaction(%Transaction{type: type, data: data}) do
    %{
      "type" => type,
      "data" => %{
        "content" => data.content,
        "code" => data.code,
        "ledger" => %{
          "uco" => %{
            "transfers" => data.ledger.uco.transfers
          },
          "token" => %{
            "transfers" =>
              Enum.map(data.ledger.token.transfers, fn t ->
                %{
                  "to" => t.to,
                  "amount" => t.amount,
                  "tokenAddress" => t.token_address,
                  "tokenId" => t.token_id
                }
              end)
          }
        }
      }
    }
  end
end
