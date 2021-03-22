defmodule Uniris.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Uniris network.
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

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  require Logger

  @doc ~S"""
  Parse a smart contract code and return its representation

  ## Examples

      iex> "
      ...>    condition origin_family: biometric
      ...>
      ...>    condition inherit,
      ...>       content: regex_match?(\"^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$\")
      ...>
      ...>    actions triggered_by: datetime, at: 1601039923 do
      ...>      set_type hosting
      ...>      set_content \"Mr.X: 10, Mr.Y: 8\"
      ...>    end
      ...> "
      ...> |> Contracts.parse()
      {:ok,
        %Contract{
          conditions: %Conditions{
            inherit: [
              content: {:regex_match?, [line: 4], ["^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$"]}
            ],
            origin_family: :biometric,
            transaction: nil
          },
          constants: %Constants{
            contract: nil,
            transaction: nil
          },
          triggers: [
            %Trigger{
              actions: {:__block__, [], [
                {:set_type, [line: 7], [{:hosting, [line: 7], nil}]},
                {:set_content, [line: 8], ["Mr.X: 10, Mr.Y: 8"]}
              ]},
              opts: [at: ~U[2020-09-25 13:18:43Z]],
              type: :datetime
            }
          ]
        }}
  """
  @spec parse(binary()) :: {:ok, Contract.t()} | {:error, binary()}
  def parse(contract_code) when is_binary(contract_code) do
    case Interpreter.parse(contract_code) do
      {:ok, %Contract{triggers: [_ | _], conditions: %Conditions{inherit: []}}} ->
        {:error, "missing inherit constraints"}

      {:ok, contract = %Contract{}} ->
        {:ok, contract}

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
       conditions: %Conditions{inherit: inherit_constraints}
     }} = Interpreter.parse(code)

    constants = [
      previous: Constants.from_transaction(prev_tx),
      next: Constants.from_transaction(next_tx)
    ]

    default_inherit_conditions = [
      code: nil,
      content: nil,
      uco_transfers: nil,
      nft_transfer: nil
    ]

    inherit_conditions = Keyword.merge(default_inherit_conditions, inherit_constraints)

    with {:inherit, true} <-
           {:inherit, Enum.all?(inherit_conditions, &do_valid_condition?(&1, constants))},
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

  defp do_valid_condition?({field, nil}, previous: prev, next: next) do
    Keyword.get(prev, field) == Keyword.get(next, field)
  end

  defp do_valid_condition?({field, value}, constants) do
    next = Keyword.get(constants, :next)
    subject = Keyword.get(next, field)

    result = Interpreter.execute_inherit_condition(Macro.to_string(value), subject)

    if is_boolean(result) do
      result == true
    else
      result == Keyword.get(next, field)
    end
  end

  defp valid_from_trigger?(%Trigger{type: :datetime, opts: [at: datetime]}, %Transaction{
         timestamp: timestamp
       }) do
    DateTime.diff(timestamp, datetime) == 0
  end

  defp valid_from_trigger?(%Trigger{type: :interval, opts: [at: interval]}, %Transaction{
         timestamp: timestamp
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
