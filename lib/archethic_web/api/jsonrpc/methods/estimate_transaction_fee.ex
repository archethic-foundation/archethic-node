defmodule ArchethicWeb.API.JsonRPC.Method.EstimateTransactionFee do
  @moduledoc """
  JsonRPC method to estimate transaction fee for a given transaction
  """

  alias Archethic.TransactionChain
  alias Archethic.Mining
  alias Archethic.Mining.SmartContractValidation
  alias Archethic.OracleChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.API.JsonRPC.TransactionSchema

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
  @spec execute(params :: Transaction.t()) :: {:ok, result :: map()}
  def execute(tx) do
    timestamp = DateTime.utc_now()

    previous_price =
      timestamp |> OracleChain.get_last_scheduling_date() |> OracleChain.get_uco_price()

    uco_eur = previous_price |> Keyword.fetch!(:eur)
    uco_usd = previous_price |> Keyword.fetch!(:usd)

    resolved_recipients = resolve_recipient_addresses(tx)

    recipients_fee =
      case SmartContractValidation.validate_contract_calls(resolved_recipients, tx, timestamp) do
        {:ok, fees} -> fees
        _ -> 0
      end

    # not possible to have a contract's state here
    fee = Mining.get_transaction_fee(tx, nil, uco_usd, timestamp, nil, recipients_fee)

    result = %{"fee" => fee, "rates" => %{"usd" => uco_usd, "eur" => uco_eur}}
    {:ok, result}
  end

  defp resolve_recipient_addresses(
         tx = %Transaction{data: %TransactionData{recipients: recipients}}
       ) do
    resolved_addresses = TransactionChain.resolve_transaction_addresses!(tx)

    Enum.reduce(recipients, [], fn r = %Recipient{address: address}, acc ->
      resolved = Map.get(resolved_addresses, address)
      [%Recipient{r | address: resolved} | acc]
    end)
    |> Enum.reverse()
  end
end
