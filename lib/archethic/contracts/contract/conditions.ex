defmodule Archethic.Contracts.ContractConditions do
  @moduledoc """
  Represents the smart contract conditions
  """

  defstruct [:subjects, args: []]

  defmodule Subjects do
    @moduledoc false

    alias Archethic.SharedSecrets
    alias Archethic.TransactionChain.Transaction

    defstruct [
      :address,
      :type,
      :content,
      :code,
      :authorized_keys,
      :secrets,
      :uco_transfers,
      :token_transfers,
      :previous_public_key,
      :timestamp,
      origin_family: :all
    ]

    @type t :: %__MODULE__{
            address: binary() | Macro.t() | nil,
            type: Transaction.transaction_type() | nil,
            content: binary() | Macro.t() | nil,
            code: binary() | Macro.t() | nil,
            authorized_keys: map() | Macro.t() | nil,
            secrets: list(binary()) | Macro.t() | nil,
            uco_transfers: map() | Macro.t() | nil,
            token_transfers: map() | Macro.t() | nil,
            previous_public_key: binary() | Macro.t() | nil,
            origin_family: SharedSecrets.origin_family() | :all,
            timestamp: DateTime.t() | nil
          }
  end

  @type t :: %__MODULE__{args: list(binary()), subjects: Subjects.t()}

  def empty?(%__MODULE__{
        args: [],
        subjects: %Subjects{
          address: nil,
          type: nil,
          content: nil,
          code: nil,
          authorized_keys: nil,
          secrets: nil,
          uco_transfers: nil,
          token_transfers: nil,
          previous_public_key: nil,
          timestamp: nil
        }
      }),
      do: true

  def empty?(%__MODULE__{}), do: false
end
