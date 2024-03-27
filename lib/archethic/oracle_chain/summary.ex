defmodule Archethic.OracleChain.Summary do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  defstruct [:transactions, :aggregated]

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()) | Enumerable.t(),
          aggregated:
            %{
              DateTime.t() => map()
            }
            | nil
        }

  @doc ~S"""
  Aggregate the oracle chain data into a single map

  ## Examples

      iex> %Summary{
      ...>   transactions: [
      ...>     %Transaction{
      ...>       validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:10:00Z]},
      ...>       data: %TransactionData{content: "{\"uco\":{\"eur\":0.02, \"usd\":0.018}}"}
      ...>     },
      ...>     %Transaction{
      ...>       validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:00:00Z]},
      ...>       data: %TransactionData{content: "{\"uco\":{\"eur\":0.021, \"usd\":0.019}}"}
      ...>     }
      ...>   ]
      ...> }
      ...> |> Summary.aggregate()
      %Summary{
        transactions: [
          %Transaction{
            validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:10:00Z]},
            data: %TransactionData{content: "{\"uco\":{\"eur\":0.02, \"usd\":0.018}}"}
          },
          %Transaction{
            validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:00:00Z]},
            data: %TransactionData{content: "{\"uco\":{\"eur\":0.021, \"usd\":0.019}}"}
          }
        ],
        aggregated: %{
          ~U[2021-04-29 13:00:00Z] => %{"uco" => %{"eur" => 0.021, "usd" => 0.019}},
          ~U[2021-04-29 13:10:00Z] => %{"uco" => %{"eur" => 0.02, "usd" => 0.018}}
        }
      }
  """
  @spec aggregate(t()) :: t()
  def aggregate(summary = %__MODULE__{transactions: transactions}) do
    aggregated =
      transactions
      |> Stream.map(fn %Transaction{
                         data: %TransactionData{content: content},
                         validation_stamp: %ValidationStamp{timestamp: timestamp}
                       } ->
        data = Jason.decode!(content)

        {DateTime.truncate(timestamp, :second), data}
      end)
      |> Enum.into(%{})

    %{summary | aggregated: aggregated}
  end

  @doc ~S"""
  Verify if the aggregated data is correct from the list transaction passed

  ## Examples

      iex> %Summary{
      ...>   aggregated: %{
      ...>     ~U[2021-04-29 13:00:00Z] => %{"uco" => %{"eur" => 0.021, "usd" => 0.019}},
      ...>     ~U[2021-04-29 13:10:00Z] => %{"uco" => %{"eur" => 0.02, "usd" => 0.018}}
      ...>   },
      ...>   transactions: [
      ...>     %Transaction{
      ...>       validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:10:00Z]},
      ...>       data: %TransactionData{content: "{\"uco\":{\"eur\":0.02, \"usd\":0.018}}"}
      ...>     },
      ...>     %Transaction{
      ...>       validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:00:00Z]},
      ...>       data: %TransactionData{content: "{\"uco\":{\"eur\":0.021, \"usd\":0.019}}"}
      ...>     }
      ...>   ]
      ...> }
      ...> |> Summary.verify?()
      true
  """
  @spec verify?(t()) :: boolean()
  def verify?(%__MODULE__{transactions: transactions, aggregated: aggregated}) do
    %__MODULE__{aggregated: transaction_lookup} =
      %__MODULE__{transactions: transactions} |> aggregate()

    Enum.all?(aggregated, fn {timestamp, data} ->
      case Map.get(transaction_lookup, timestamp) do
        ^data ->
          true

        _ ->
          false
      end
    end)
  end

  @doc """
  Format aggregated data into a JSON
  """
  @spec aggregated_to_json(t()) :: binary()

  def aggregated_to_json(%__MODULE__{
        aggregated: aggregated_data
      }) do
    aggregated_data
    |> Enum.map(&{DateTime.to_unix(elem(&1, 0)), elem(&1, 1)})
    |> Enum.into(%{})
    |> Jason.encode!()
  end
end
