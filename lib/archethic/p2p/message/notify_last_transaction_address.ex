defmodule Archethic.P2P.Message.NotifyLastTransactionAddress do
  @moduledoc """
  Represents a message with to notify a pool of the last address of a previous address
  """
  @enforce_keys [:last_address, :genesis_address, :previous_address, :timestamp]
  defstruct [:last_address, :genesis_address, :previous_address, :timestamp]

  alias Archethic.Crypto
  alias Archethic.Contracts
  alias Archethic.SelfRepair
  alias Archethic.P2P
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          last_address: Crypto.versioned_hash(),
          genesis_address: Crypto.versioned_hash(),
          previous_address: Crypto.versioned_hash(),
          timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          genesis_address: genesis_address,
          last_address: last_address,
          previous_address: previous_address,
          timestamp: timestamp
        },
        _
      ) do
    with {local_last_address, _} <- TransactionChain.get_last_address(genesis_address),
         true <- local_last_address != last_address do
      if local_last_address == previous_address do
        TransactionChain.register_last_address(genesis_address, last_address, timestamp)

        # Stop potential previous smart contract
        Contracts.stop_contract(local_last_address)
      else
        authorized_nodes = P2P.authorized_and_available_nodes()
        SelfRepair.update_last_address(local_last_address, authorized_nodes)
      end
    end

    %Ok{}
  end
end
