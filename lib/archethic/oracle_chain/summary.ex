defmodule ArchEthic.OracleChain.Summary do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  defstruct [:transactions, :previous_date, :date, :aggregated]

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()) | Enumerable.t(),
          previous_date: DateTime.t() | nil,
          date: DateTime.t() | nil,
          aggregated:
            %{
              DateTime.t() => map()
            }
            | nil
        }

  @doc ~S"""
  Aggregate the oracle chain data into a single map

  ## Examples

      iex> %Summary{ transactions: [
      ...>   %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:10:00Z]}, data: %TransactionData{content: "{\"uco\":{\"eur\":0.02, \"usd\":0.018}}"}},
      ...>   %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:00:00Z]}, data: %TransactionData{content: "{\"uco\":{\"eur\":0.021, \"usd\":0.019}}"}}
      ...> ]}
      ...> |> Summary.aggregate()
      %Summary{
        transactions: [
          %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:10:00Z]}, data: %TransactionData{content: "{\"uco\":{\"eur\":0.02, \"usd\":0.018}}"}},
          %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:00:00Z]}, data: %TransactionData{content: "{\"uco\":{\"eur\":0.021, \"usd\":0.019}}"}}
        ],
        aggregated: %{
          ~U[2021-04-29 13:00:00Z] => %{ "uco" => %{ "eur" => 0.021, "usd" => 0.019 }},
          ~U[2021-04-29 13:10:00Z] => %{ "uco" => %{ "eur" => 0.02, "usd" => 0.018 }}
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
      ...>      ~U[2021-04-29 13:00:00Z] => %{ "uco" => %{ "eur" => 0.021, "usd" => 0.019 }},
      ...>      ~U[2021-04-29 13:10:00Z] => %{ "uco" => %{ "eur" => 0.02, "usd" => 0.018 }}
      ...>   },
      ...>   transactions: [
      ...>     %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:10:00Z]}, data: %TransactionData{content: "{\"uco\":{\"eur\":0.02, \"usd\":0.018}}"}},
      ...>     %Transaction{validation_stamp: %ValidationStamp{timestamp: ~U[2021-04-29 13:00:00Z]}, data: %TransactionData{content: "{\"uco\":{\"eur\":0.021, \"usd\":0.019}}"}}
      ...>   ]
      ...> } |> Summary.verify?()
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
  Build a transaction from the oracle chain's summary
  """
  @spec to_transaction(t()) :: Transaction.t()
  def to_transaction(%__MODULE__{
        aggregated: aggregated_data,
        previous_date: previous_date,
        date: date
      }) do
    {prev_pub, prev_pv} = Crypto.derive_oracle_keypair(previous_date)
    {next_pub, _} = Crypto.derive_oracle_keypair(date)

    Transaction.new(
      :oracle_summary,
      %TransactionData{
        code: """
          # We stop the inheritance of transaction by ensuring no other
          # summary transaction will continue on this chain
          condition inherit: [ content: "" ]
        """,
        content:
          aggregated_data
          |> Enum.map(&{DateTime.to_unix(elem(&1, 0)), elem(&1, 1)})
          |> Enum.into(%{})
          |> Jason.encode!()
      },
      prev_pv,
      prev_pub,
      next_pub
    )
  end
end
