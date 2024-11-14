defmodule Archethic.P2P.Message.UpdateLastAddress do
  @moduledoc """
  Inform a  shard to start repair.
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.SelfRepair
  alias Archethic.TransactionChain
  alias Archethic.Utils

  @typedoc """
  address is an address which the destination node is elected to store
  it is NOT the last address
  """
  @type t :: %__MODULE__{
          address: Crypto.prepended_hash()
        }

  @spec process(t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: address}, _) do
    nodes = P2P.authorized_and_available_nodes()

    cond do
      not Election.chain_storage_node?(address, Crypto.first_node_public_key(), nodes) ->
        :ok

      not TransactionChain.transaction_exists?(address) ->
        # here we detect that current node does not store what it is supposed to
        # we could repair the transaction then update last address
        :ok

      true ->
        SelfRepair.update_last_address(address, nodes)
    end

    %Ok{}
  end

  def serialize(%__MODULE__{address: address}) do
    address
  end

  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {%__MODULE__{address: address}, rest}
  end
end
