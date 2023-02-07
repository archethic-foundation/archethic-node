defmodule Archethic.Contracts.Interpreter.Version0 do
  @moduledoc false

  require Logger

  alias __MODULE__.ActionInterpreter
  alias __MODULE__.ConditionInterpreter

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConditions, as: Conditions
  alias Archethic.Contracts.Interpreter

  @doc ~S"""
  Parse a smart contract code and return the filtered AST representation.

  The parser uses a whitelist of instructions, the rest will be rejected

  ## Examples

      iex> Version0.parse("
      ...>    condition transaction: [
      ...>      content: regex_match?(\"^Mr.Y|Mr.X{1}$\"),
      ...>      origin_family: biometric
      ...>    ]
      ...>
      ...>    condition inherit: [
      ...>       content: regex_match?(\"hello\")
      ...>    ]
      ...>
      ...>    condition oracle: [
      ...>      content: json_path_extract(\"$.uco.eur\") > 1
      ...>    ]
      ...>
      ...>    actions triggered_by: datetime, at: 1603270603 do
      ...>      new_content = \"Sent #{1_040_000_000}\"
      ...>      set_type transfer
      ...>      set_content new_content
      ...>      add_uco_transfer to: \"22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10\", amount: 1_040_000_000
      ...>    end
      ...>
      ...>    actions triggered_by: oracle do
      ...>      set_content \"uco price changed\"
      ...>    end
      ...> ")
      {:ok,
        %Contract{
          conditions: %{
             inherit: %Archethic.Contracts.ContractConditions{
                content: {
                      :==,
                      [line: 7],
                      [
                        true,
                        {{:., [line: 7], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.Library], [:Library]}, :regex_match?]}, [line: 7], [{:get_in, [line: 7], [{:scope, [line: 7], nil}, ["next", "content"]]}, "hello"]}
                      ]
                },
                authorized_keys: nil,
                code: nil,
                token_transfers: nil,
                origin_family: :all,
                previous_public_key: nil,
                type: nil,
                uco_transfers: nil
             },
            oracle: %Archethic.Contracts.ContractConditions{
                 content: {
                      :>,
                      [line: 11],
                      [
                        {
                          :==,
                          [line: 11],
                          [
                            {:get_in, [line: 11], [{:scope, [line: 11], nil}, ["transaction", "content"]]},
                            {{:., [line: 11], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.Library], [:Library]}, :json_path_extract]}, [line: 11], [{:get_in, [line: 11], [{:scope, [line: 11], nil}, ["transaction", "content"]]}, "$.uco.eur"]}
                          ]
                        },
                        1
                      ]
                  },
                 authorized_keys: nil,
              code: nil,
                 token_transfers: nil,
                 origin_family: :all,
                 previous_public_key: nil,
                 type: nil,
                 uco_transfers: nil
             },
             transaction: %Archethic.Contracts.ContractConditions{
                 content: {
                      :==,
                      [line: 2],
                      [
                        true,
                        {{:., [line: 2], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.Library], [:Library]}, :regex_match?]}, [line: 2], [{:get_in, [line: 2], [{:scope, [line: 2], nil}, ["transaction", "content"]]}, "^Mr.Y|Mr.X{1}$"]}
                      ]
                 },
                 origin_family: :biometric,
                 authorized_keys: nil,
                 code: nil,
                 token_transfers: nil,
                 previous_public_key: nil,
                 type: nil,
                 uco_transfers: nil
             }
         },
         constants: %Archethic.Contracts.ContractConstants{},
         next_transaction: %Transaction{ data: %TransactionData{}},
         triggers: %{
           {:datetime, ~U[2020-10-21 08:56:43Z]} => {:__block__, [],
              [
                {:=, [line: 15], [{:scope, [line: 15], nil}, {{:., [line: 15], [{:__aliases__, [line: 15], [:Map]}, :put]}, [line: 15], [{:scope, [line: 15], nil}, "new_content", "Sent 1040000000"]}]},
                {
                  :=,
                  [line: 16],
                  [
                    {:scope, [line: 16], nil},
                    {:update_in, [line: 16], [{:scope, [line: 16], nil}, ["next_transaction"], {:&, [line: 16], [{{:., [line: 16], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.TransactionStatements], [:TransactionStatements]}, :set_type]}, [line: 16], [{:&, [line: 16], [1]}, "transfer"]}]}]}
                  ]
                },
                {
                  :=,
                  [line: 17],
                  [
                    {:scope, [line: 17], nil},
                    {:update_in, [line: 17], [{:scope, [line: 17], nil}, ["next_transaction"], {:&, [line: 17], [{{:., [line: 17], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.TransactionStatements], [:TransactionStatements]}, :set_content]}, [line: 17], [{:&, [line: 17], [1]}, {:get_in, [line: 17], [{:scope, [line: 17], nil}, ["new_content"]]}]}]}]}
                  ]
                },
                {
                  :=,
                  [line: 18],
                  [
                    {:scope, [line: 18], nil},
                    {:update_in, [line: 18], [{:scope, [line: 18], nil}, ["next_transaction"], {:&, [line: 18], [{{:., [line: 18], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.TransactionStatements], [:TransactionStatements]}, :add_uco_transfer]}, [line: 18], [{:&, [line: 18], [1]}, [{"to", "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"}, {"amount", 1040000000}]]}]}]}
                  ]
                }
              ]},
           :oracle => {
              :=,
              [line: 22],
              [
                {:scope, [line: 22], nil},
                {:update_in, [line: 22], [{:scope, [line: 22], nil}, ["next_transaction"], {:&, [line: 22], [{{:., [line: 22], [{:__aliases__, [alias: Archethic.Contracts.Interpreter.Version0.TransactionStatements], [:TransactionStatements]}, :set_content]}, [line: 22], [{:&, [line: 22], [1]}, "uco price changed"]}]}]}
              ]
           }
          }
        }
      }

     Returns an error when there are invalid trigger options

       iex> Version0.parse("
       ...>    actions triggered_by: datetime, at: 0000000 do
       ...>    end
       ...> ")
       {:error, "invalid datetime's trigger"}

     Returns an error when a invalid term is provided

       iex> Version0.parse("
       ...>    actions triggered_by: transaction do
       ...>       System.user_home
       ...>    end
       ...> ")
       {:error, "unexpected term - System - L2"}
  """
  @spec parse(code :: binary()) :: {:ok, Contract.t()} | {:error, reason :: binary()}
  def parse(code) when is_binary(code) do
    with {:ok, ast} <- Interpreter.sanitize_code(code),
         {:ok, contract} <- parse_contract(ast, %Contract{}) do
      {:ok, %{contract | version: {0, 0, 1}}}
    else
      {:error, {meta, {_, info}, token}} ->
        {:error, Interpreter.format_error_reason({token, meta, []}, info)}

      {:error, {meta, info, token}} ->
        {:error, Interpreter.format_error_reason({token, meta, []}, info)}

      {:error, {:unexpected_term, ast}} ->
        {:error, Interpreter.format_error_reason(ast, "unexpected term")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(Conditions.t(), map()) :: bool()
  def valid_conditions?(conditions, constants) do
    ConditionInterpreter.valid_conditions?(conditions, constants)
  end

  defp parse_contract({:__block__, _, ast}, contract) do
    parse_ast_block(ast, contract)
  end

  defp parse_contract(ast, contract) do
    parse_ast(ast, contract)
  end

  defp parse_ast_block([ast | rest], contract) do
    case parse_ast(ast, contract) do
      {:ok, contract} ->
        parse_ast_block(rest, contract)

      {:error, _} = e ->
        e
    end
  end

  defp parse_ast_block([], contract), do: {:ok, contract}

  defp parse_ast(ast = {{:atom, "condition"}, _, _}, contract) do
    case ConditionInterpreter.parse(ast) do
      {:ok, condition_type, condition} ->
        {:ok, Contract.add_condition(contract, condition_type, condition)}

      {:error, _} = e ->
        e
    end
  end

  defp parse_ast(ast = {{:atom, "actions"}, _, _}, contract) do
    case ActionInterpreter.parse(ast) do
      {:ok, trigger_type, actions} ->
        {:ok, Contract.add_trigger(contract, trigger_type, actions)}

      {:error, _} = e ->
        e
    end
  end

  defp parse_ast(ast, _), do: {:error, {:unexpected_term, ast}}
end