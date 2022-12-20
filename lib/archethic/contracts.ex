defmodule Archethic.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Archethic network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Contract
  alias __MODULE__.ContractConditions, as: Conditions
  alias __MODULE__.ContractConstants, as: Constants
  alias __MODULE__.Interpreter
  alias __MODULE__.Loader
  alias __MODULE__.TransactionLookup
  alias __MODULE__.Worker

  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker, as: CronDateChecker

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Contracts.ContractConstants, as: Constants

  require Logger

  @extended_mode? Mix.env() != :prod

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
      {
              :ok,
              %Archethic.Contracts.Contract{
                conditions: %{
                  inherit: %Archethic.Contracts.ContractConditions{
                    address: nil,
                    authorized_keys: nil,
                    code: nil,
                    content: {
                      :==,
                      [line: 2],
                      [true, {{:., [line: 2], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Legacy.Library], [:Library]}, :regex_match?]}, [line: 2], [{:get_in, [line: 2], [{:scope, [line: 2], nil}, ["next", "content"]]}, "^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$"]}]
                    },
                    origin_family: :biometric,
                    previous_public_key: nil,
                    secrets: nil,
                    timestamp: nil,
                    token_transfers: nil,
                    type: nil,
                    uco_transfers: nil
                  },
                  oracle: %Archethic.Contracts.ContractConditions{address: nil, authorized_keys: nil, code: nil, content: nil, origin_family: :all, previous_public_key: nil, secrets: nil, timestamp: nil, token_transfers: nil, type: nil, uco_transfers: nil},
                  transaction: %Archethic.Contracts.ContractConditions{address: nil, authorized_keys: nil, code: nil, content: nil, origin_family: :all, previous_public_key: nil, secrets: nil, timestamp: nil, token_transfers: nil, type: nil, uco_transfers: nil}
                },
                constants: %Archethic.Contracts.ContractConstants{contract: nil, transaction: nil},
                next_transaction: %Archethic.TransactionChain.Transaction{
                  address: nil,
                  cross_validation_stamps: [],
                  data: %Archethic.TransactionChain.TransactionData{
                    code: "",
                    content: "",
                    ledger: %Archethic.TransactionChain.TransactionData.Ledger{token: %Archethic.TransactionChain.TransactionData.TokenLedger{transfers: []}, uco: %Archethic.TransactionChain.TransactionData.UCOLedger{transfers: []}},
                    ownerships: [],
                    recipients: []
                  },
                  origin_signature: nil,
                  previous_public_key: nil,
                  previous_signature: nil,
                  type: nil,
                  validation_stamp: nil,
                  version: 1
                },
                triggers: %{
                  {:datetime, ~U[2020-09-25 13:18:43Z]} => {
                    :__block__,
                    [],
                    [
                      {
                        :__block__,
                        [],
                        [
                          {
                            :=,
                            [line: 7],
                            [{:scope, [line: 7], nil}, {:update_in, [line: 7], [{:scope, [line: 7], nil}, ["next_transaction"], {:&, [line: 7], [{{:., [line: 7], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Legacy.TransactionStatements], [:TransactionStatements]}, :set_type]}, [line: 7], [{:&, [line: 7], [1]}, "hosting"]}]}]}]
                          },
                          {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [], [{:scope, [], nil}]}
                        ]
                      },
                      {
                        :__block__,
                        [],
                        [
                          {
                            :=,
                            [line: 8],
                            [{:scope, [line: 8], nil}, {:update_in, [line: 8], [{:scope, [line: 8], nil}, ["next_transaction"], {:&, [line: 8], [{{:., [line: 8], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Legacy.TransactionStatements], [:TransactionStatements]}, :set_content]}, [line: 8], [{:&, [line: 8], [1]}, "Mr.X: 10, Mr.Y: 8"]}]}]}]
                          },
                          {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [], [{:scope, [], nil}]}
                        ]
                      }
                    ]
                  }
                },
                version: 0
              }
            }
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
          Map.has_key?(triggers, :transaction) and Conditions.empty?(transaction_conditions) ->
            {:error, "missing transaction conditions"}

          Map.has_key?(triggers, :oracle) and Conditions.empty?(oracle_conditions) ->
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
  @spec load_transaction(Transaction.t(), list()) :: :ok
  defdelegate load_transaction(tx, opts), to: Loader

  @spec accept_new_contract?(Transaction.t() | nil, Transaction.t(), DateTime.t()) :: boolean()
  def accept_new_contract?(nil, _, _), do: true
  def accept_new_contract?(%Transaction{data: %TransactionData{code: ""}}, _, _), do: true

  def accept_new_contract?(
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        next_tx = %Transaction{},
        date = %DateTime{}
      ) do
    {:ok,
     %Contract{
       version: version,
       triggers: triggers,
       conditions: %{inherit: inherit_conditions}
     }} = Interpreter.parse(code)

    constants = %{
      "previous" => Constants.from_transaction(prev_tx),
      "next" => Constants.from_transaction(next_tx)
    }

    with :ok <- validate_conditions(version, inherit_conditions, constants),
         :ok <- validate_triggers(triggers, next_tx, date) do
      true
    else
      {:error, _} ->
        false
    end
  end

  @doc """
  Simulate the execution of the contract hold in prev_tx with the inputs of next_tx, at a certain date
  """

  @spec simulate_contract_execution(Transaction.t(), Transaction.t(), DateTime.t()) ::
          :ok | {:error, reason :: term()}
  def simulate_contract_execution(
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        incoming_tx = %Transaction{},
        date = %DateTime{}
      ) do
    case Interpreter.parse(code) do
      {:ok,
       %Contract{
         version: version,
         triggers: triggers,
         conditions: conditions
       }} ->
        triggers
        |> Enum.find_value(:ok, fn {trigger_type, trigger_code} ->
          do_simulate_contract(
            version,
            trigger_code,
            trigger_type,
            conditions,
            prev_tx,
            incoming_tx,
            date
          )
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_simulate_contract(
         version,
         trigger_code,
         trigger_type,
         conditions,
         prev_tx,
         incoming_tx,
         date
       ) do
    case valid_from_trigger?(trigger_type, incoming_tx, date) do
      true ->
        case validate_transaction_conditions(
               version,
               trigger_type,
               conditions,
               prev_tx,
               incoming_tx
             ) do
          :ok ->
            validate_inherit_conditions(version, trigger_code, conditions, prev_tx, incoming_tx)

          {:error, reason} ->
            {:error, reason}
        end

      false ->
        {:error, :invalid_trigger}
    end
  end

  defp validate_transaction_conditions(
         version,
         trigger_type,
         %{transaction: transaction_conditions},
         prev_tx,
         incoming_tx
       ) do
    case trigger_type do
      :transaction ->
        constants_prev = %{
          "transaction" => Constants.from_transaction(incoming_tx),
          "contract" => Constants.from_transaction(prev_tx)
        }

        case Interpreter.valid_conditions?(version, transaction_conditions, constants_prev) do
          true ->
            :ok

          false ->
            {:error, :invalid_transaction_conditions}
        end

      _ ->
        :ok
    end
  end

  defp validate_inherit_conditions(
         version,
         trigger_code,
         %{inherit: inherit_conditions},
         prev_tx,
         incoming_tx
       ) do
    prev_constants = %{
      "transaction" => Constants.from_transaction(incoming_tx),
      "contract" => Constants.from_transaction(prev_tx)
    }

    case Interpreter.execute_trigger(version, trigger_code, prev_constants) do
      nil ->
        :ok

      next_transaction = %Transaction{} ->
        %{next_transaction: next_transaction} =
          %{next_transaction: next_transaction, previous_transaction: prev_tx}
          |> Worker.chain_type()
          |> Worker.chain_code()
          |> Worker.chain_ownerships()

        constants_both = %{
          "previous" => Constants.from_transaction(prev_tx),
          "next" => Constants.from_transaction(next_transaction)
        }

        case Interpreter.valid_conditions?(version, inherit_conditions, constants_both) do
          true ->
            :ok

          false ->
            {:error, :invalid_inherit_conditions}
        end
    end
  end

  defp validate_conditions(version, inherit_conditions, constants) do
    if Interpreter.valid_conditions?(version, inherit_conditions, constants) do
      :ok
    else
      Logger.error("Inherit constraints not respected")
      {:error, :invalid_inherit_constraints}
    end
  end

  defp validate_triggers(triggers, _next_tx, _date) when map_size(triggers) == 0, do: :ok

  defp validate_triggers(triggers, next_tx, date) do
    if Enum.any?(triggers, fn {trigger_type, _} ->
         valid_from_trigger?(trigger_type, next_tx, date)
       end) do
      :ok
    else
      Logger.error("Transaction not processed by a valid smart contract trigger")
      {:error, :invalid_triggers_execution}
    end
  end

  defp valid_from_trigger?(
         {:datetime, datetime},
         %Transaction{},
         validation_date = %DateTime{}
       ) do
    # Accept time drifing for 10seconds
    DateTime.diff(validation_date, datetime) >= 0 and
      DateTime.diff(validation_date, datetime) < 10
  end

  defp valid_from_trigger?(
         {:interval, interval},
         %Transaction{},
         validation_date = %DateTime{}
       ) do
    interval
    |> CronParser.parse!(@extended_mode?)
    |> CronDateChecker.matches_date?(DateTime.to_naive(validation_date))
  end

  defp valid_from_trigger?(_, _, _), do: true

  @doc """
  List the address of the transaction which has contacted a smart contract
  """
  @spec list_contract_transactions(contract_address :: binary()) ::
          list(
            {transaction_address :: binary(), transaction_timestamp :: DateTime.t(),
             protocol_version :: non_neg_integer()}
          )
  defdelegate list_contract_transactions(address),
    to: TransactionLookup,
    as: :list_contract_transactions

  @doc """
  Termine a smart contract execution when a new transaction on the chain happened
  """
  @spec stop_contract(binary()) :: :ok
  defdelegate stop_contract(address), to: Loader
end
