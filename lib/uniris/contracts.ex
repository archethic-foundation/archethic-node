defmodule Uniris.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Uniris network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Contract
  alias __MODULE__.Contract.Conditions
  alias __MODULE__.Contract.Constants
  alias __MODULE__.Interpreter
  alias __MODULE__.Loader
  alias __MODULE__.TransactionLookup
  alias __MODULE__.Worker

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  @doc ~S"""
  Parse a smart contract code to check if it's valid or not

  ## Examples

      iex> "
      ...>    condition origin_family: biometric
      ...>    condition inherit: regex_match?(next_transaction.content, \"^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$\")
      ...>    actions triggered_by: datetime, at: 1601039923 do
      ...>      set_type hosting
      ...>      set_content \"Mr.X: 10, Mr.Y: 8\"
      ...>    end  
      ...> "
      ...> |> Contracts.valid_contract?()
      true
  """
  @spec valid_contract?(binary()) :: boolean()
  def valid_contract?(contract_code) when is_binary(contract_code) do
    case parse(contract_code) do
      {:ok, _} ->
        true

      _ ->
        false
    end
  end

  @doc ~S"""
  Parse a smart contract code and return its representation

  ## Examples

      iex> "
      ...>    condition origin_family: biometric
      ...>    condition inherit: regex_match?(next_transaction.content, \"^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$\")
      ...>    actions triggered_by: datetime, at: 1601039923 do
      ...>      set_type hosting
      ...>      set_content \"Mr.X: 10, Mr.Y: 8\"
      ...>    end  
      ...> "
      ...> |> Contracts.parse()
      {:ok,
        %Contract{
          conditions: %Conditions{
            inherit: {:regex_match?, [line: 2], [{{:., [line: 2], [{:next_transaction, [line: 2], nil}, :content]}, [no_parens: true, line: 2], []}, "^(Mr.X: ){1}([0-9]+), (Mr.Y: ){1}([0-9])+$"]},
            origin_family: :biometric,
            transaction: nil
          },
          constants: %Constants{
            contract: nil,
            transaction: nil
          },
          triggers: [
            %Trigger{
              actions: {:__block__, [], [{:set_type, [line: 4], [{:hosting, [line: 4], nil}]}, {:set_content, [line: 5], ["Mr.X: 10, Mr.Y: 8"]}]},
              opts: [at: ~U[2020-09-25 13:18:43Z]],
              type: :datetime
            }
          ]
        }}
  """
  @spec parse(binary()) ::
          {:ok, Contract.t()}
          | {:error, Interpreter.parsing_error()}
          | {:error, :missing_inherit_constraints}
  def parse(contract_code) when is_binary(contract_code) do
    case Interpreter.parse(contract_code) do
      {:ok, %Contract{conditions: %Conditions{inherit: nil}}} ->
        {:error, :missing_inherit_constraints}

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

  def accept_new_contract(
        prev_tx = %Transaction{data: %TransactionData{code: code}},
        new_tx = %Transaction{}
      ) do
    {:ok, %Contract{conditions: %Conditions{inherit: inherit_constraints}}} =
      Interpreter.parse(code)

    inherit_constants = [
      previous_transaction: Constants.from_transaction(prev_tx),
      next_transaction: Constants.from_transaction(new_tx)
    ]

    Interpreter.can_execute?(inherit_constraints, inherit_constants)
  end

  @doc """
  List the address of the transaction which has contacted a smart contract 
  """
  @spec list_contract_transactions(binary()) :: list(binary())
  defdelegate list_contract_transactions(address),
    to: TransactionLookup,
    as: :list_contract_transactions
end
