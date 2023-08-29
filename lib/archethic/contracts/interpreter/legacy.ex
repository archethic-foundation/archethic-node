defmodule Archethic.Contracts.Interpreter.Legacy do
  @moduledoc false

  require Logger

  alias __MODULE__.ActionInterpreter
  alias __MODULE__.ConditionInterpreter

  alias Archethic.Contracts.Contract
  alias Archethic.Contracts.ContractConstants, as: Constants
  alias Archethic.Contracts.ContractConditions.Subjects, as: ConditionsSubjects
  alias Archethic.Contracts.Interpreter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  @doc ~S"""
  Parse a smart contract code and return the filtered AST representation.

  The parser uses a whitelist of instructions, the rest will be rejected

  ## Examples

      iex> {:ok, ast} = Interpreter.sanitize_code("
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
      ...> Legacy.parse(ast)
      {
        :ok,
        %Archethic.Contracts.Contract{
          conditions: %{
            {:transaction, nil, nil} => %Archethic.Contracts.ContractConditions{
              args: [],
              subjects: %Archethic.Contracts.ContractConditions.Subjects{
                address: nil,
                authorized_keys: nil,
                code: nil,
                content: {
                  :==,
                  [line: 3],
                  [
                    true,
                    {
                      {
                        :.,
                        [line: 3],
                        [
                          {
                            :__aliases__,
                            [alias: Archethic.Contracts.Interpreter.Legacy.Library],
                            [:Library]
                          },
                          :regex_match?
                        ]
                      },
                      [line: 3],
                      [
                        {
                          :get_in,
                          [line: 3],
                          [{:scope, [line: 3], nil}, ["transaction", "content"]]
                        },
                        "^Mr.Y|Mr.X{1}$"
                      ]
                    }
                  ]
                },
                origin_family: :biometric,
                previous_public_key: nil,
                secrets: nil,
                timestamp: nil,
                token_transfers: nil,
                type: nil,
                uco_transfers: nil
              }
            },
            inherit: %Archethic.Contracts.ContractConditions{
              args: [],
              subjects: %Archethic.Contracts.ContractConditions.Subjects{
                address: nil,
                authorized_keys: nil,
                code: nil,
                content: {
                  :==,
                  [line: 8],
                  [
                    true,
                    {
                      {
                        :.,
                        [line: 8],
                        [
                          {
                            :__aliases__,
                            [alias: Archethic.Contracts.Interpreter.Legacy.Library],
                            [:Library]
                          },
                          :regex_match?
                        ]
                      },
                      [line: 8],
                      [
                        {
                          :get_in,
                          [line: 8],
                          [{:scope, [line: 8], nil}, ["next", "content"]]
                        },
                        "hello"
                      ]
                    }
                  ]
                },
                origin_family: :all,
                previous_public_key: nil,
                secrets: nil,
                timestamp: nil,
                token_transfers: nil,
                type: nil,
                uco_transfers: nil
              }
            },
            oracle: %Archethic.Contracts.ContractConditions{
              args: [],
              subjects: %Archethic.Contracts.ContractConditions.Subjects{
                address: nil,
                authorized_keys: nil,
                code: nil,
                content: {
                  :>,
                  [line: 12],
                  [
                    {
                      {
                        :.,
                        [line: 12],
                        [
                          {
                            :__aliases__,
                            [alias: Archethic.Contracts.Interpreter.Legacy.Library],
                            [:Library]
                          },
                          :json_path_extract
                        ]
                      },
                      [line: 12],
                      [
                        {
                          :get_in,
                          [line: 12],
                          [{:scope, [line: 12], nil}, ["transaction", "content"]]
                        },
                        "$.uco.eur"
                      ]
                    },
                    1
                  ]
                },
                origin_family: :all,
                previous_public_key: nil,
                secrets: nil,
                timestamp: nil,
                token_transfers: nil,
                type: nil,
                uco_transfers: nil
              }
            }
          },
          constants: %Archethic.Contracts.ContractConstants{
            contract: nil,
            transaction: nil
          },
          functions: %{},
          next_transaction: %Archethic.TransactionChain.Transaction{
            address: nil,
            cross_validation_stamps: [],
            data: %Archethic.TransactionChain.TransactionData{
              code: "",
              content: "",
              ledger: %Archethic.TransactionChain.TransactionData.Ledger{
                token: %Archethic.TransactionChain.TransactionData.TokenLedger{
                  transfers: []
                },
                uco: %Archethic.TransactionChain.TransactionData.UCOLedger{
                  transfers: []
                }
              },
              ownerships: [],
              recipients: []
            },
            origin_signature: nil,
            previous_public_key: nil,
            previous_signature: nil,
            type: nil,
            validation_stamp: nil,
            version: 2
          },
          triggers: %{
            :oracle => %{
              args: [],
              ast: {
                :__block__,
                [],
                [
                  {
                    :=,
                    [line: 23],
                    [
                      {:scope, [line: 23], nil},
                      {
                        :update_in,
                        [line: 23],
                        [
                          {:scope, [line: 23], nil},
                          ["next_transaction"],
                          {
                            :&,
                            [line: 23],
                            [
                              {
                                {
                                  :.,
                                  [line: 23],
                                  [
                                    {
                                      :__aliases__,
                                      [
                                        alias: Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                      ],
                                      [:TransactionStatements]
                                    },
                                    :set_content
                                  ]
                                },
                                [line: 23],
                                [{:&, [line: 23], [1]}, "uco price changed"]
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  },
                  {
                    {
                      :.,
                      [],
                      [{:__aliases__, [alias: false], [:Function]}, :identity]
                    },
                    [],
                    [{:scope, [], nil}]
                  }
                ]
              }
            },
            {:datetime, ~U[2020-10-21 08:56:43Z]} => %{
              args: [],
              ast: {
                :__block__,
                [],
                [
                  {
                    :=,
                    [line: 16],
                    [
                      {:scope, [line: 16], nil},
                      {
                        {
                          :.,
                          [line: 16],
                          [{:__aliases__, [line: 16], [:Map]}, :put]
                        },
                        [line: 16],
                        [
                          {:scope, [line: 16], nil},
                          "new_content",
                          "Sent 1040000000"
                        ]
                      }
                    ]
                  },
                  {
                    :__block__,
                    [],
                    [
                      {
                        :=,
                        [line: 17],
                        [
                          {:scope, [line: 17], nil},
                          {
                            :update_in,
                            [line: 17],
                            [
                              {:scope, [line: 17], nil},
                              ["next_transaction"],
                              {
                                :&,
                                [line: 17],
                                [
                                  {
                                    {
                                      :.,
                                      [line: 17],
                                      [
                                        {
                                          :__aliases__,
                                          [
                                            alias: Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                          ],
                                          [:TransactionStatements]
                                        },
                                        :set_type
                                      ]
                                    },
                                    [line: 17],
                                    [{:&, [line: 17], [1]}, "transfer"]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      },
                      {
                        {
                          :.,
                          [],
                          [{:__aliases__, [alias: false], [:Function]}, :identity]
                        },
                        [],
                        [{:scope, [], nil}]
                      }
                    ]
                  },
                  {
                    :__block__,
                    [],
                    [
                      {
                        :=,
                        [line: 18],
                        [
                          {:scope, [line: 18], nil},
                          {
                            :update_in,
                            [line: 18],
                            [
                              {:scope, [line: 18], nil},
                              ["next_transaction"],
                              {
                                :&,
                                [line: 18],
                                [
                                  {
                                    {
                                      :.,
                                      [line: 18],
                                      [
                                        {
                                          :__aliases__,
                                          [
                                            alias: Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                          ],
                                          [:TransactionStatements]
                                        },
                                        :set_content
                                      ]
                                    },
                                    [line: 18],
                                    [
                                      {:&, [line: 18], [1]},
                                      {
                                        :get_in,
                                        [line: 18],
                                        [
                                          {:scope, [line: 18], nil},
                                          ["new_content"]
                                        ]
                                      }
                                    ]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      },
                      {
                        {
                          :.,
                          [],
                          [{:__aliases__, [alias: false], [:Function]}, :identity]
                        },
                        [],
                        [{:scope, [], nil}]
                      }
                    ]
                  },
                  {
                    :__block__,
                    [],
                    [
                      {
                        :=,
                        [line: 19],
                        [
                          {:scope, [line: 19], nil},
                          {
                            :update_in,
                            [line: 19],
                            [
                              {:scope, [line: 19], nil},
                              ["next_transaction"],
                              {
                                :&,
                                [line: 19],
                                [
                                  {
                                    {
                                      :.,
                                      [line: 19],
                                      [
                                        {
                                          :__aliases__,
                                          [
                                            alias: Archethic.Contracts.Interpreter.Legacy.TransactionStatements
                                          ],
                                          [:TransactionStatements]
                                        },
                                        :add_uco_transfer
                                      ]
                                    },
                                    [line: 19],
                                    [
                                      {:&, [line: 19], [1]},
                                      [
                                        {
                                          "to",
                                          "22368B50D3B2976787CFCC27508A8E8C67483219825F998FC9D6908D54D0FE10"
                                        },
                                        {"amount", 1040000000}
                                      ]
                                    ]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      },
                      {
                        {
                          :.,
                          [],
                          [{:__aliases__, [alias: false], [:Function]}, :identity]
                        },
                        [],
                        [{:scope, [], nil}]
                      }
                    ]
                  }
                ]
              }
            }
          },
          version: 0
        }
      }

     Returns an error when there are invalid trigger options

       iex> {:ok, ast} = Interpreter.sanitize_code("
       ...>    actions triggered_by: datetime, at: 0000000 do
       ...>    end
       ...> ")
       ...> Legacy.parse(ast)
       {:error, "invalid datetime's trigger"}

     Returns an error when a invalid term is provided

       iex> {:ok, ast} = Interpreter.sanitize_code("
       ...>    actions triggered_by: transaction do
       ...>       System.user_home
       ...>    end
       ...> ")
       ...> Legacy.parse(ast)
       {:error, "unexpected term - System - L3"}
  """
  @spec parse(ast :: Macro.t()) :: {:ok, Contract.t()} | {:error, reason :: binary()}
  def parse(ast) do
    case parse_contract(ast, %Contract{}) do
      {:ok, contract} ->
        {:ok, %{contract | version: 0}}

      {:error, {:unexpected_term, ast}} ->
        {:error, Interpreter.format_error_reason(ast, "unexpected term")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Return true if the given conditions are valid on the given constants
  """
  @spec valid_conditions?(ConditionsSubjects.t(), map()) :: bool()
  def valid_conditions?(conditions, constants) do
    ConditionInterpreter.valid_conditions?(conditions, constants)
  end

  @doc """
  Execute the trigger/action code.
  May return a new transaction or nil
  """
  @spec execute_trigger(Macro.t(), map()) :: Transaction.t() | nil
  def execute_trigger(ast, constants) do
    case ActionInterpreter.execute(ast, constants) do
      nil ->
        # contract did not produce a next_tx
        nil

      next_tx_to_prepare ->
        # contract produce a next_tx but we need to feed previous values to it
        chain_transaction(
          Constants.to_transaction(constants["contract"]),
          next_tx_to_prepare
        )
    end
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

  # -----------------------------------------
  # chain next tx
  # -----------------------------------------
  defp chain_transaction(previous_transaction, next_transaction) do
    %{next_transaction: next_tx} =
      %{next_transaction: next_transaction, previous_transaction: previous_transaction}
      |> chain_type()
      |> chain_code()
      |> chain_ownerships()

    next_tx
  end

  defp chain_type(
         acc = %{
           next_transaction: %Transaction{type: nil},
           previous_transaction: _
         }
       ) do
    put_in(acc, [:next_transaction, Access.key(:type)], :contract)
  end

  defp chain_type(acc), do: acc

  defp chain_code(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{code: ""}},
           previous_transaction: %Transaction{data: %TransactionData{code: previous_code}}
         }
       ) do
    put_in(acc, [:next_transaction, Access.key(:data, %{}), Access.key(:code)], previous_code)
  end

  defp chain_code(acc), do: acc

  defp chain_ownerships(
         acc = %{
           next_transaction: %Transaction{data: %TransactionData{ownerships: []}},
           previous_transaction: %Transaction{
             data: %TransactionData{ownerships: previous_ownerships}
           }
         }
       ) do
    put_in(
      acc,
      [:next_transaction, Access.key(:data, %{}), Access.key(:ownerships)],
      previous_ownerships
    )
  end

  defp chain_ownerships(acc), do: acc
end
