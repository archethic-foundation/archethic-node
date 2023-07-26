defmodule ArchethicWeb.API.JsonRPC.Method.EstimateTransactionFee do
  @moduledoc """
  JsonRPC method to estimate transaction fee for a given transaction
  """

  alias Archethic.Mining
  alias Archethic.OracleChain
  alias Archethic.TransactionChain.Transaction

  alias ArchethicWeb.API.JsonRPC.Method
  alias ArchethicWeb.API.TransactionPayload

  alias ArchethicWeb.WebUtils

  @behaviour Method

  @doc """
  Validate parameter to match the expected JSON pattern
  """
  @spec validate_params(param :: map()) ::
          {:ok, params :: Transaction.t()} | {:error, reasons :: list()}
  def validate_params(params) do
    case TransactionPayload.changeset(params) do
      changeset = %{valid?: true} ->
        tx = changeset |> TransactionPayload.to_map() |> Transaction.cast()
        {:ok, tx}

      changeset ->
        reasons = Ecto.Changeset.traverse_errors(changeset, &WebUtils.translate_error/1)

        {:error, reasons}
    end
  end

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

    fee = Mining.get_transaction_fee(tx, uco_usd, timestamp)

    result = %{"fee" => fee, "rates" => %{"usd" => uco_usd, "eur" => uco_eur}}
    {:ok, result}
  end
end
