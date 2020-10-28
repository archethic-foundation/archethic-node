defmodule Uniris.Contracts do
  @moduledoc """
  Handle smart contracts based on a new language running in an custom interpreter for Uniris network.
  Each smart contract is register and supervised as long running process to interact with later on.
  """

  alias __MODULE__.Contract
  alias __MODULE__.Interpreter
  alias __MODULE__.Loader
  alias __MODULE__.Worker

  alias Uniris.TransactionChain.Transaction

  @doc ~S"""
  Parse a smart contract code to check if it's valid or not

  ## Examples

      iex> Contracts.valid_contract? "
      ...>   trigger datetime: 1573745454
      ...>   actions do
      ...>    \"Closing votes\"
      ...>   end
      ...> "
      true

  Returns false when an unexpected symbol is found.
  Allows only whitelisted symbols to prevent access to critical functions and ensures safety.

      iex> Contracts.valid_contract? "
      ...>   actions do
      ...>     System.user_home
      ...>   end
      ...> "
      false

  Returns false when type check errors for triggers or conditions

      iex> Contracts.valid_contract? "
      ...>   trigger datetime: 0000000111
      ...> "
      false

      iex> Contracts.valid_contract? "
      ...>   condition post_paid_fee: \"0000000000011198718\"
      ...> "
      false

  """
  @spec valid_contract?(binary()) :: boolean()
  def valid_contract?(contract_code) when is_binary(contract_code) do
    case Interpreter.parse(contract_code) do
      {:ok, _} ->
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Parse a smart contract code and return its representation

  ## Examples

      iex> "
      ...>    trigger datetime: 1601039923
      ...>    condition origin_family: biometric
      ...>    actions do
      ...>
      ...>    end  
      ...> "
      ...> |> Contracts.parse()
      {:ok, %Contract{
        actions: {:__block__, [], []},
        triggers: %Triggers{
          datetime: ~U[2020-09-25 13:18:43Z]
        },
        conditions: %Conditions{
          response: nil,
          inherit: nil,
          post_paid_fee: nil,
          origin_family: :biometric
        }
      }}
  """
  @spec parse(binary()) :: {:ok, Contract.t()} | {:error, Interpreter.parsing_error()}
  def parse(code) do
    case Interpreter.parse(code) do
      {:ok, ast} ->
        {:ok, Contract.from_ast(ast)}

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Same a `parse/1` but raise if the contract is not valid
  """
  @spec parse!(binary()) :: Contract.t()
  def parse!(contract_code) when is_binary(contract_code) do
    {:ok, ast} = Interpreter.parse(contract_code)
    Contract.from_ast(ast)
  end

  @doc """
  Execute a contract retrieved from its address with an incoming transaction
  and validate it according to the smart contract conditions
  """
  def execute(address, tx = %Transaction{}) when is_binary(address) do
    Worker.execute(address, tx)
  end

  @doc """
  Load transaction into the Smart Contract context leveraging the interpreter
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(tx), to: Loader
end
