defmodule Uniris.Interpreter do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Uniris network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.AST
  alias __MODULE__.Contract
  alias __MODULE__.ContractSupervisor
  alias Uniris.Transaction

  @doc ~S"""
  Parse a smart contract code to check if it's valid or not

  ## Examples

      iex> Uniris.Interpreter.valid_contract? "
      ...>   trigger datetime: 1573745454
      ...>   actions do
      ...>    \"Closing votes\"
      ...>   end
      ...> "
      true

  Returns false when an unexpected symbol is found.
  Allows only whitelisted symbols to prevent access to critical functions and ensures safety.

      iex> Uniris.Interpreter.valid_contract? "
      ...>   actions do
      ...>     System.user_home
      ...>   end
      ...> "
      false

  Returns false when type check errors for triggers or conditions

      iex> Uniris.Interpreter.valid_contract? "
      ...>   trigger datetime: 0000000111
      ...> "
      false

      iex> Uniris.Interpreter.valid_contract? "
      ...>   condition post_paid_fee: \"0000000000011198718\"
      ...> "
      false

  """
  @spec valid_contract?(binary()) :: boolean()
  def valid_contract?(contract_code) do
    case AST.parse(contract_code) do
      {:ok, _} ->
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Parse and create a new contract long running process

  The triggers are extracted to be stored for self triggerable capability trough internal messages

  The actions is extracted as AST and can be used to provide analysis (static, fuzzing,etc.) and will be used
  for trigger or actions processing.

  The conditions are extracted as AST also are used before response execution and
  may be checked during the validation of incoming transaction
  """
  @spec new_contract(Transaction.pending()) ::
          :ok | {:error, {:invalid_syntax, reason :: binary()}}
  def new_contract(tx = %Transaction{data: %{code: contract_code}}) do
    case AST.parse(contract_code) do
      {:ok, ast} ->
        DynamicSupervisor.start_child(ContractSupervisor, {Contract, transaction: tx, ast: ast})

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Execute a contract retrieved from its address with an incoming transaction
  and validate it according to the smart contract conditions
  """
  def execute(address, tx = %Transaction{}) do
    Contract.execute(address, tx)
  end
end
