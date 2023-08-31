defmodule ArchethicWeb.API.JsonRPC.Method.SendTransaction do
  @moduledoc """
  JsonRPC method to send a new transaction in the network
  """

  alias Archethic.TransactionChain.Transaction

  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.API.JsonRPC.TransactionSchema

  alias ArchethicWeb.TransactionSubscriber

  @behaviour Method

  @doc """
  Validate parameter to match the expected JSON pattern
  """
  @spec validate_params(param :: map()) ::
          {:ok, params :: Transaction.t()} | {:error, reasons :: map()}
  def validate_params(%{"transaction" => transaction_params}) do
    case TransactionSchema.validate(transaction_params) do
      :ok ->
        {:ok, TransactionSchema.to_transaction(transaction_params)}

      :error ->
        {:error, %{"transaction" => "Must be an object"}}

      {:error, reasons} ->
        {:error, reasons}
    end
  end

  def validate_params(_), do: {:error, %{"transaction" => "Is required"}}

  @doc """
  Execute the function to send a new tranaction in the network
  """
  @spec execute(params :: Transaction.t()) ::
          {:ok, result :: map()}
          | {:error, :transaction_exists, message :: binary()}
  def execute(tx = %Transaction{address: address}) do
    if Archethic.transaction_exists?(address) do
      {:error, :transaction_exists, "Transaction #{Base.encode16(address)} already exists"}
    else
      :ok = Archethic.send_new_transaction(tx, forward?: true)
      TransactionSubscriber.register(tx.address, System.monotonic_time())

      result = %{transaction_address: Base.encode16(address), status: "pending"}
      {:ok, result}
    end
  end
end
