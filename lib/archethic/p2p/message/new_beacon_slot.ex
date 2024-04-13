defmodule Archethic.P2P.Message.NewBeaconSlot do
  @moduledoc """
  Represents a message for a new beacon slot transaction
  """

  @enforce_keys [:slot]
  defstruct [:slot]

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.Utils

  require Logger

  @type t :: %__MODULE__{
          slot: Slot.t()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{slot: slot = %Slot{subset: subset, slot_time: slot_time}},
        %{sender_public_key: node_public_key}
      ) do
    summary_time = BeaconChain.next_summary_date(slot_time)
    node_list = P2P.authorized_and_available_nodes(summary_time, true)

    beacon_summary_nodes =
      Election.beacon_storage_nodes(
        subset,
        summary_time,
        node_list,
        Election.get_storage_constraints()
      )

    # Load BeaconChain's slot only for the summary nodes
    with true <- Utils.key_in_node_list?(beacon_summary_nodes, Crypto.first_node_public_key()),
         :ok <- BeaconChain.load_slot(slot, node_public_key) do
      %Ok{}
    else
      false ->
        Logger.error("Unexpected beacon slot broadcast")
        %Error{reason: :network_issue}

      :error ->
        %Error{reason: :invalid_transaction}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{slot: slot}),
    do: <<Slot.serialize(slot) |> Utils.wrap_binary()::bitstring>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {slot = %Slot{}, rest} = Slot.deserialize(rest)

    {
      %__MODULE__{slot: slot},
      rest
    }
  end
end
