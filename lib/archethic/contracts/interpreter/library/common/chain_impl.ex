defmodule Archethic.Contracts.Interpreter.Library.Common.ChainImpl do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Legacy
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Chain
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.Interpreter.Constants

  alias Archethic.Crypto

  alias Archethic.Tag

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.Utils

  @behaviour Chain
  use Tag

  @tag [:io]
  @impl Chain
  defdelegate get_genesis_address(address),
    to: Legacy.Library,
    as: :get_genesis_address

  @tag [:io]
  @impl Chain
  def get_first_transaction_address(address) do
    try do
      Legacy.Library.get_first_transaction_address(address)
    rescue
      _ -> nil
    end
  end

  @tag [:io]
  @impl Chain
  def get_last_address(address) do
    function = "Chain.get_last_address"

    address
    |> get_binary_address(function)
    |> Archethic.get_last_transaction_address()
    |> then(fn
      {:ok, last_address} -> Base.encode16(last_address)
      {:error, _} -> raise Library.Error, message: "Network issue in #{function}"
    end)
  end

  @tag [:io]
  @impl Chain
  def get_last_transaction(address) do
    function = "Chain.get_last_transaction"

    address
    |> get_binary_address(function)
    |> Archethic.get_last_transaction()
    |> then(fn
      {:ok, tx} -> Constants.from_transaction(tx)
      {:error, _} -> nil
    end)
  end

  @tag [:io]
  @impl Chain
  def get_genesis_public_key(public_key) do
    try do
      Legacy.Library.get_genesis_public_key(public_key)
    rescue
      _ -> nil
    end
  end

  @tag [:io]
  @impl Chain
  def get_transaction(address) do
    address
    |> UtilsInterpreter.get_address("Chain.get_transaction/1")
    |> Archethic.search_transaction()
    |> then(fn
      {:ok, tx} -> Constants.from_transaction(tx)
      {:error, _} -> nil
    end)
  end

  @impl Chain
  def get_burn_address(), do: LedgerOperations.burning_address() |> Base.encode16()

  @impl Chain
  def get_previous_address(previous_public_key) when is_binary(previous_public_key),
    do: previous_address(previous_public_key)

  def get_previous_address(%{"previous_public_key" => previous_public_key}),
    do: previous_address(previous_public_key)

  def get_previous_address(arg),
    do:
      raise(Library.Error,
        message:
          "Invalid arg for Chain.get_previous_address(), expected string or map, got #{inspect(arg)}"
      )

  defp previous_address(previous_public_key) do
    with {:ok, pub_key} <- Base.decode16(previous_public_key),
         true <- Crypto.valid_public_key?(pub_key) do
      pub_key |> Crypto.derive_address() |> Base.encode16()
    else
      _ ->
        raise Library.Error,
          message:
            "Invalid previous public key in Chain.get_previous_address(), got #{inspect(previous_public_key)}"
    end
  end

  @impl Chain
  @tag [:io]
  def get_balance(address_hex) do
    function = "Chain.get_balance"

    %{uco: uco_amount, token: tokens} =
      address_hex |> get_binary_address(function) |> fetch_balance(function)

    tokens =
      Enum.reduce(tokens, %{}, fn {{token_address, token_id}, amount}, acc ->
        key = %{"token_address" => Base.encode16(token_address), "token_id" => token_id}
        Map.put(acc, key, Utils.from_bigint(amount))
      end)

    %{"uco" => Utils.from_bigint(uco_amount), "tokens" => tokens}
  end

  @impl Chain
  @tag [:io]
  def get_uco_balance(address_hex) do
    function = "Chain.get_balance"
    %{uco: uco_amount} = address_hex |> get_binary_address(function) |> fetch_balance(function)

    Utils.from_bigint(uco_amount)
  end

  @impl Chain
  @tag [:io]
  def get_token_balance(address_hex, token_address_hex, token_id \\ 0)

  def get_token_balance(address_hex, token_address_hex, token_id) do
    function = "Chain.get_token_balance"
    token_address = get_binary_address(token_address_hex, function)
    %{token: tokens} = address_hex |> get_binary_address(function) |> fetch_balance(function)

    tokens |> Map.get({token_address, token_id}, 0) |> Utils.from_bigint()
  end

  @impl Chain
  @tag [:io]
  def get_tokens_balance(address_hex) do
    function = "Chain.get_tokens_balance"

    %{token: tokens} = address_hex |> get_binary_address(function) |> fetch_balance(function)

    Enum.reduce(tokens, %{}, fn {{token_address, token_id}, amount}, acc ->
      key = %{"token_address" => Base.encode16(token_address), "token_id" => token_id}
      Map.put(acc, key, Utils.from_bigint(amount))
    end)
  end

  @impl Chain
  @tag [:io]
  def get_tokens_balance(address_hex, requested_tokens) do
    function = "Chain.get_tokens_balance"

    %{token: tokens} = address_hex |> get_binary_address(function) |> fetch_balance(function)

    Enum.reduce(
      requested_tokens,
      %{},
      fn token = %{"token_address" => token_address_hex, "token_id" => token_id}, acc ->
        key = {get_binary_address(token_address_hex, function), token_id}
        amount = Map.get(tokens, key, 0) |> Utils.from_bigint()
        Map.put(acc, token, amount)
      end
    )
  end

  defp get_binary_address(address_hex, function) do
    with {:ok, address} <- Base.decode16(address_hex, case: :mixed),
         true <- Crypto.valid_address?(address) do
      address
    else
      _ ->
        raise Library.Error,
          message: "Invalid address in #{function}, got #{inspect(address_hex)}"
    end
  end

  defp fetch_balance(address, function) do
    case Archethic.fetch_genesis_address(address) do
      {:ok, genesis_address} -> Archethic.get_balance(genesis_address)
      _ -> raise Library.Error, message: "Network issue in #{function}"
    end
  end
end
