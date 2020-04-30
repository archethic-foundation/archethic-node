defmodule UnirisCore.TransactionData do
  @moduledoc """
  Represents any transaction data block
  """
  alias __MODULE__.Ledger
  alias __MODULE__.Keys

  defstruct recipients: [], ledger: %Ledger{}, code: "", keys: %Keys{}, content: ""

  @typedoc """
  Transaction data is composed from:
  - Recipients: list of address recipients for smart contract interactions
  - Ledger: Movement operations on UCO, NFT or Stock ledger
  - Code: Contains the smart contract code including triggers, conditions and actions
  - Keys: Map of key owners and delegations
  - Content: Free content to store any data as binary
  """
  @type t :: %__MODULE__{
          recipients: list(binary()),
          ledger: Ledger.t(),
          code: binary(),
          keys: Keys.t(),
          content: binary()
        }
end
