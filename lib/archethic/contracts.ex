defmodule ArchEthic.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for ArchEthic network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Contract
  alias __MODULE__.Contract.Conditions
  alias __MODULE__.Contract.Constants
  alias __MODULE__.Contract.Trigger
  alias __MODULE__.Interpreter
  alias __MODULE__.Loader
  alias __MODULE__.TransactionLookup
  alias __MODULE__.Worker

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker, as: CronDateChecker

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  require Logger

  @doc ~S"""
  Parse a smart contract code and return its representation

  ## Examples

      iex> "
      ...>    condition inherit: [
      ...>       content: regex_match?(\"^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$\"),
      ...>       origin_family: biometric
      ...>    ]
      ...>
      ...>    actions triggered_by: datetime, at: 1601039923 do
      ...>      set_type hosting
      ...>      set_content \"Mr.X: 10, Mr.Y: 8\"
      ...>    end
      ...> "
      ...> |> Contracts.parse()
      {:ok,
        %Contract{
          conditions: %{
            inherit: %Conditions{
              content: {:==, [line: 2], [
                true,
                {
                  {:., [line: 2], [{:__aliases__, [alias: ArchEthic.Contracts.Interpreter.Library], [:Library]}, :regex_match?]},
                  [line: 2],
                  [{:get_in, [line: 2], [{:scope, [line: 2], nil}, ["next", "content"]]}, "^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$"]
                }
              ]},
              origin_family: :biometric
            },
            transaction: %Conditions{},
            oracle: %Conditions{}
          },
          constants: %Constants{
            contract: nil,
            transaction: nil
          },
          triggers: [
            %Trigger{
              actions: {:__block__, [], [
                {
                  :=,
                  [line: 7],
                  [
                    {:scope, [line: 7], nil},
                    {:update_in, [line: 7], [{:scope, [line: 7], nil}, ["contract"], {:&, [line: 7], [{{:., [line: 7], [{:__aliases__, [alias: ArchEthic.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_type]}, [line: 7], [{:&, [line: 7], [1]}, "hosting"]}]}]}
                  ]
                },
                {
                  :=,
                  [line: 8],
                  [
                    {:scope, [line: 8], nil},
                    {:update_in, [line: 8], [{:scope, [line: 8], nil}, ["contract"], {:&, [line: 8], [{{:., [line: 8], [{:__aliases__, [alias: ArchEthic.Contracts.Interpreter.TransactionStatements], [:TransactionStatements]}, :set_content]}, [line: 8], [{:&, [line: 8], [1]}, "Mr.X: 10, Mr.Y: 8"]}]}]}
                  ]
                }
              ]},
              opts: [at: ~U[2020-09-25 13:18:43Z]],
              type: :datetime
            }
          ]
        }}
  """
  @spec parse(binary()) :: {:ok, Contract.t()} | {:error, binary()}
  def parse(contract_code) when is_binary(contract_code) do
    start = System.monotonic_time()

    case Interpreter.parse(contract_code) do
      {:ok,
       contract = %Contract{
         triggers: triggers,
         conditions: %{transaction: transaction_conditions, oracle: oracle_conditions}
       }} ->
        :telemetry.execute([:archethic, :contract, :parsing], %{
          duration: System.monotonic_time() - start
        })

        cond do
          Enum.any?(triggers, &(&1.type == :transaction)) and
              Conditions.empty?(transaction_conditions) ->
            {:error, "missing transaction conditions"}

          Enum.any?(triggers, &(&1.type == :oracle)) and Conditions.empty?(oracle_conditions) ->
            {:error, "missing oracle conditions"}

          true ->
            {:ok, contract}
        end

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Same a `parse/1` but raise if the contract is not valid
  """
  @spec parse!(binary()) :: Contract.t()
  def parse!(contract_code) when is_binary(contract_code) do
    {:ok, contract} = parse(contract_code)
    contract
  end

  @doc """
  Execute a contract retrieved from its address with an incoming transaction
  and validate it according to the smart contract conditions
  """
  @spec execute(binary(), Transaction.t()) :: :ok | {:error, :invalid_condition}
  defdelegate execute(address, tx), to: Worker

  @doc """
  Load transaction into the Smart Contract context leveraging the interpreter
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(tx), to: Loader

  @spec accept_new_contract?(Transaction.t() | nil, Transaction.t()) :: boolean()
  def accept_new_contract?(nil, _), do: true
  def accept_new_contract?(%Transaction{data: %TransactionData{code: ""}}, _), do: true

  def accept_new_contract?(
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        next_tx = %Transaction{}
      ) do
    {:ok,
     %Contract{
       triggers: triggers,
       conditions: %{inherit: inherit_conditions}
     }} = Interpreter.parse(code)

    constants = %{
      "previous" => Constants.from_transaction(prev_tx),
      "next" => Constants.from_transaction(next_tx)
    }

    with {:inherit, true} <-
           {:inherit, Interpreter.valid_conditions?(inherit_conditions, constants)},
         {:origin, true} <- {:origin, Enum.all?(triggers, &valid_from_trigger?(&1, next_tx))} do
      true
    else
      {:inherit, false} ->
        Logger.error("Inherit constraints not respected")

        false

      {:origin, false} ->
        Logger.error("Transaction not processed by a valid smart contract trigger")
        false
    end
  end

  defp valid_from_trigger?(%Trigger{type: :datetime, opts: [at: datetime]}, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    DateTime.diff(timestamp, datetime) == 0
  end

  defp valid_from_trigger?(%Trigger{type: :interval, opts: [at: interval]}, %Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    interval
    |> CronParser.parse!(true)
    |> CronDateChecker.matches_date?(DateTime.to_naive(timestamp))
  end

  defp valid_from_trigger?(%Trigger{type: :transaction}, _), do: true

  @doc """
  List the address of the transaction which has contacted a smart contract
  """
  @spec list_contract_transactions(binary()) :: list({binary(), DateTime.t()})
  defdelegate list_contract_transactions(address),
    to: TransactionLookup,
    as: :list_contract_transactions

  @doc """
  Termine a smart contract execution when a new transaction on the chain happened
  """
  @spec stop_contract(binary()) :: :ok
  defdelegate stop_contract(address), to: Loader
end
