defmodule UnirisInterpreter.Contract do
  @moduledoc """
  Parsed smart contract instance
  """

  alias UnirisChain.Transaction

  defstruct triggers: [],
            conditions: [
              response: Macro.escape(true),
              inherit: Macro.escape(true),
              origin_family: :any
            ],
            actions: {:__block__, [], []},
            constants: []

  @typedoc """
  Origin family is the category of device originating transactions
  """
  @type origin_family :: :any | :biometric | :software

  @typedoc """
  Uniris Smart Contract is defined by three main components:
  - Triggers: Nodes are able to self trigger smart contract based on the extraction of
  these elements and stored locally.
    - Datetime: Timestamp when the action will be executed
  - Conditions: Requirements to be true before execute the contract
    - Response: Define the rules to accept the incoming transaction response
    - Origin Family: Define the accepted family of devices originating the transactions
    - Post Paid Fee: Define the address will be in charge to pay the fees for the transactions
    - Inherit: Inherited constraints ruling the next transactions on the contract chain
  - Actions: Contract logic executed against a transaction response and condition interacting
  with the smart contract

  Additional information as constants are extracted from the AST to be used
  inside triggers, conditions or actions
  """
  @type t :: %__MODULE__{
          triggers: [] | [datetime: integer()],
          conditions: [
            response: Macro.t(),
            origin_family: origin_family(),
            post_paid_fee: binary(),
            inherit: Macro.t()
          ],
          actions: Macro.t(),
          constants: Keyword.t()
        }

  @doc """
  Create the smart contract instance from parsed AST
  """
  @spec new({:actions, [], [[do: Macro.t()]]}, Transaction.t()) :: __MODULE__.t()
  def new({:actions, _, [[do: actions]]} = _ast, tx = %Transaction{}),
    do: %__MODULE__{
      actions: actions,
      constants: [
        keys: tx.data.keys,
        ledger: tx.data.ledger
      ]
    }

  @spec new(
          {:__block__, [],
           [
             {:@, [], [{atom(), [], [term()]}]}
             | {:trigger, [], Keyword.t()}
             | {:condition, [], Keyword.t()}
             | {:actions, [], [[do: Macro.t()]]}
           ]},
          Transaction.t()
        ) :: __MODULE__.t()
  def new({:__block__, [], elems} = _ast, tx = %Transaction{}) do
    elems
    |> Enum.reduce(
      %__MODULE__{
        constants: [
          keys: tx.data.keys,
          ledger: tx.data.ledger
        ]
      },
      fn elem, contract ->
        do_build_contract(elem, contract)
      end
    )
  end

  defp do_build_contract({:@, _, [{token, _, [value]}]}, contract = %__MODULE__{}) do
    %{contract | constants: Keyword.put(contract.constants, token, value)}
  end

  defp do_build_contract({:trigger, _, [props]}, contract = %__MODULE__{}) do
    Map.update!(contract, :triggers, &Keyword.merge(&1, props))
  end

  defp do_build_contract({:condition, _, [props]}, contract = %__MODULE__{}) do
    Map.update!(contract, :conditions, &Keyword.merge(&1, props))
  end

  defp do_build_contract(
         {:actions, _, [[do: {:__block__, _, _} = actions]]},
         contract = %__MODULE__{}
       ) do
    %{contract | actions: actions}
  end

  defp do_build_contract({:actions, _, [[do: elems]]}, contract = %__MODULE__{}) do
    %{contract | actions: elems}
  end
end
