defmodule Archethic.Contracts.Interpreter.Library.Common.ChainImpl do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Legacy
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Chain
  alias Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter
  alias Archethic.Contracts.ContractConstants, as: Constants

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
    with {:ok, address} <- Base.decode16(address_hex),
         true <- Crypto.valid_address?(address),
         {:ok, last_address} <- Archethic.get_last_transaction_address(address),
         {:ok, %{uco: uco_amount, token: tokens}} <- Archethic.get_balance(last_address) do
      tokens =
        Enum.reduce(tokens, %{}, fn {{token_address, token_id}, amount}, acc ->
          key = %{"token_address" => Base.encode16(token_address), "token_id" => token_id}
          Map.put(acc, key, Utils.from_bigint(amount))
        end)

      %{"uco" => Utils.from_bigint(uco_amount), "tokens" => tokens}
    else
      _ ->
        # Can only catch _ otherwise dialyzer is not happy
        raise Library.Error,
          message: "Invalid address in Chain.get_balance(), got #{inspect(address_hex)}"
    end
  end
end
