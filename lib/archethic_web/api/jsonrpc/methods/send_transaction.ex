defmodule ArchethicWeb.API.JsonRPC.Method.SendTransaction do
  @moduledoc """
  JsonRPC method to send a new transaction in the network
  """

  alias Archethic.TransactionChain.Transaction

  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.API.TransactionPayload

  alias ArchethicWeb.TransactionSubscriber

  alias ArchethicWeb.WebUtils

  @behaviour Method

  @doc """
  Validate parameter to match the expected JSON pattern
  """
  @spec validate_params(param :: map()) ::
          {:ok, params :: Transaction.t()} | {:error, reasons :: map()}
  def validate_params(%{"transaction" => transaction_params}) do
    case TransactionPayload.changeset(transaction_params) do
      {:ok, changeset = %{valid?: true}} ->
        tx = changeset |> TransactionPayload.to_map() |> Transaction.cast()
        {:ok, tx}

      {:ok, changeset} ->
        reasons = Ecto.Changeset.traverse_errors(changeset, &WebUtils.translate_error/1)
        {:error, reasons}

      :error ->
        {:error, %{transaction: ["must be an object"]}}
    end
  end

  def validate_params(_), do: {:error, %{transaction: ["is required"]}}

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
