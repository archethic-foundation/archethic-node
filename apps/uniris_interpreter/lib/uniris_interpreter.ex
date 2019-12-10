defmodule UnirisInterpreter do
  @moduledoc """
  Uniris provides smart contracts based on a new language for smart contracts
  running in an interpreter and helps to provide checks to predict the outputs
  to ensure its correctness
  """

  alias UnirisInterpreter.AST
  alias UnirisInterpreter.Contract
  alias UnirisChain.Transaction

  @doc ~S"""
  Parse a smart contract code to check if it's valid or not and returns a Contract instance.

  The triggers could be extracted to be stored for self triggerable capability.

  The actions is extracted as AST and can be used to provide analysis (static, fuzzing,etc.)

  The conditions are extracted as AST also are used before response execution and
  may be checked during the validation of transaction response

  ## Examples

      iex> UnirisInterpreter.parse(%UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{
      ...>   smart_contract: "
      ...>     trigger datetime: 1573745454
      ...>     actions do
      ...>      \"Closing votes\"
      ...>     end
      ...>   ",
      ...>   ledger: %{},
      ...>   keys: %{},
      ...>   content: ""
      ...>  },
      ...>  timestamp: 1573739544,
      ...>  type: :smart_contract,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      %UnirisInterpreter.Contract{
        actions: "Closing votes",
        conditions: [response: true, inherit: true, origin_family: :any],
        constants: [ keys: %{}, ledger: %{} ],
        triggers: [datetime: 1573745454]
      }

  Returns an error when an unexpected symbol is found.
  Allows only whitelisted symbols to prevent access to critical functions and ensures safety.

      iex> UnirisInterpreter.parse(%UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{
      ...>   smart_contract: "
      ...>     actions do
      ...>       System.user_home
      ...>     end
      ...>   ",
      ...>   ledger: %{},
      ...>   keys: %{},
      ...>   content: ""
      ...>  },
      ...>  timestamp: 1573739544,
      ...>  type: :smart_contract,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      {:error, {:invalid_syntax, :unexpected_token}}

  Returns type check errors for triggers or conditions

      iex> UnirisInterpreter.parse(%UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{
      ...>   smart_contract: "
      ...>     trigger datetime: 0000000111
      ...>   ",
      ...>   ledger: %{},
      ...>   keys: %{},
      ...>   content: ""
      ...>  },
      ...>  timestamp: 1573739544,
      ...>  type: :smart_contract,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      {:error, {:invalid_syntax, :invalid_timestamp}}

      iex> UnirisInterpreter.parse(%UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{
      ...>   smart_contract: "
      ...>     condition post_paid_fee: \"0000000000011198718\"
      ...>   ",
      ...>   ledger: %{},
      ...>   keys: %{},
      ...>   content: ""
      ...>  },
      ...>  timestamp: 1573739544,
      ...>  type: :smart_contract,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      {:error, {:invalid_syntax, :invalid_post_paid_address}}

  """
  @spec parse(Transaction.pending()) ::
          :ok | {:error, {:invalid_syntax, reason :: binary()}}
  def parse(tx = %Transaction{type: :smart_contract}) do
    with {:ok, ast} <- AST.parse(tx.data.smart_contract) do
      Contract.new(ast, tx)
    end
  end

  @doc ~S"""
  Execute a contract retrieved from its address with a transaction response
  and validate it according to the smart contract conditions

  ## Examples

      iex> contract = UnirisInterpreter.parse(%UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{
      ...>   smart_contract: "
      ...>     condition response: response.previous_public_key in keys.authorized
      ...>     actions do
      ...>      \"Open the door\"
      ...>     end
      ...>   ",
      ...>   ledger: %{},
      ...>   keys: %{
      ...>     authorized: ["00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023"]
      ...>   },
      ...>   content: ""
      ...>  },
      ...>  timestamp: 1573739544,
      ...>  type: :smart_contract,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      iex> UnirisInterpreter.execute(contract, %UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{},
      ...>  timestamp: 1573739544,
      ...>  type: :response,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      {:ok, "Open the door"}
  """
  @spec execute(Contract.t(), Transaction.t()) ::
          {:ok, term()} | {:error, :crypto_condition_unmatched}
  def execute(contract = %Contract{}, response = %Transaction{}) do
    context = contract.constants ++ [response: response]

    case Keyword.get(contract.conditions, :response) do
      nil ->
        with {output, _} <- Code.eval_quoted(contract.actions, context) do
          {:ok, output}
        end

      condition ->
        with {true, _} <- Code.eval_quoted(condition, context),
             {output, _} <- Code.eval_quoted(contract.actions, context) do
          {:ok, output}
        else
          _ ->
            {:error, :condition_response_not_respected}
        end
    end
  end

  @doc ~S"""
  Execute a contract retrieved from its address without involving transaction response (self trigerrable contract)

  ## Examples

      iex> contract = UnirisInterpreter.parse(%UnirisChain.Transaction{
      ...>  address: "000F05D2E3642DF988115C507C15D7E525B774B9F3777E34F4212A43A840B7F807",
      ...>  data: %{
      ...>   smart_contract: "
      ...>     trigger datetime: 1573745454
      ...>     actions do
      ...>      \"Closing votes\"
      ...>     end
      ...>   ",
      ...>   ledger: %{},
      ...>   keys: %{},
      ...>   content: ""
      ...>  },
      ...>  timestamp: 1573739544,
      ...>  type: :smart_contract,
      ...>  previous_public_key: "00135D16C39C8B66418E42AC8AA3A0E819D0927C146C0FAEC2C072B00D54313023",
      ...>  previous_signature: "1B156447122188B60EA23503C74C116C6121D7C0E821DD840C4B1B64B16FB4AADBBD902F62044BD896D68BA3BA0E56D1BC52803858FDC2AF8F5E535A0CDD1F01",
      ...>  origin_signature: "5390EFE837A60C7CA9998D3F02D4E168F383D538DE56D3B28C322BA9926E4707CF6E0FAE756213145D633379DD079CE1A748D064809EE781DD12CB942A26780A"
      ...> })
      iex> UnirisInterpreter.execute(contract)
      {:ok, "Closing votes"}
  """
  @spec execute(Contract.t()) :: {:ok, term()}
  def execute(contract = %Contract{}) do
    with {output, _} <- Code.eval_quoted(contract.actions, contract.constants) do
      {:ok, output}
    end
  end
end
