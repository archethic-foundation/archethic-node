defmodule Archethic.P2P.Message.AddMiningContext do
  @moduledoc """
  Represents a message to request the add of the context of the mining from cross validation nodes
  to the coordinator
  """
  @enforce_keys [
    :address,
    :utxos_hashes,
    :validation_node_public_key,
    :chain_storage_nodes_view,
    :beacon_storage_nodes_view,
    :io_storage_nodes_view,
    :previous_storage_nodes_public_keys
  ]
  defstruct [
    :address,
    :utxos_hashes,
    :validation_node_public_key,
    :chain_storage_nodes_view,
    :beacon_storage_nodes_view,
    :io_storage_nodes_view,
    :previous_storage_nodes_public_keys
  ]

  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          utxos_hashes: list(binary()),
          validation_node_public_key: Crypto.key(),
          chain_storage_nodes_view: bitstring(),
          beacon_storage_nodes_view: bitstring(),
          io_storage_nodes_view: bitstring(),
          previous_storage_nodes_public_keys: list(Crypto.key())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          address: tx_address,
          utxos_hashes: utxos_hashes,
          validation_node_public_key: validation_node,
          previous_storage_nodes_public_keys: previous_storage_nodes_public_keys,
          chain_storage_nodes_view: chain_storage_nodes_view,
          beacon_storage_nodes_view: beacon_storage_nodes_view,
          io_storage_nodes_view: io_storage_nodes_view
        },
        _
      ) do
    Task.Supervisor.async_nolink(
      Archethic.task_supervisors(),
      fn ->
        Mining.add_mining_context(
          tx_address,
          utxos_hashes,
          validation_node,
          previous_storage_nodes_public_keys,
          chain_storage_nodes_view,
          beacon_storage_nodes_view,
          io_storage_nodes_view
        )
      end,
      timeout: Message.get_max_timeout(),
      shutdown: :brutal_kill
    )

    %Ok{}
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx_address, rest} = Utils.deserialize_address(rest)

    {node_public_key, <<nb_previous_storage_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {previous_storage_nodes_keys, rest} =
      Utils.deserialize_public_key_list(rest, nb_previous_storage_nodes, [])

    <<
      chain_storage_nodes_view_size::8,
      chain_storage_nodes_view::bitstring-size(chain_storage_nodes_view_size),
      beacon_storage_nodes_view_size::8,
      beacon_storage_nodes_view::bitstring-size(beacon_storage_nodes_view_size),
      io_storage_nodes_view_size::8,
      io_storage_nodes_view::bitstring-size(io_storage_nodes_view_size),
      rest::bitstring
    >> = rest

    {utxos_hashes_length, rest} = VarInt.get_value(rest)

    {utxos_hashes, rest} = deserialize_utxos_hashes(rest, [], utxos_hashes_length)

    {%__MODULE__{
       address: tx_address,
       utxos_hashes: utxos_hashes,
       validation_node_public_key: node_public_key,
       chain_storage_nodes_view: chain_storage_nodes_view,
       beacon_storage_nodes_view: beacon_storage_nodes_view,
       io_storage_nodes_view: io_storage_nodes_view,
       previous_storage_nodes_public_keys: previous_storage_nodes_keys
     }, rest}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        address: address,
        utxos_hashes: utxos_hashes,
        validation_node_public_key: validation_node_public_key,
        chain_storage_nodes_view: chain_storage_nodes_view,
        beacon_storage_nodes_view: beacon_storage_nodes_view,
        io_storage_nodes_view: io_storage_nodes_view,
        previous_storage_nodes_public_keys: previous_storage_nodes_public_keys
      }) do
    utxos_hashes_serialized =
      utxos_hashes
      |> :erlang.list_to_binary()

    utxos_hashes_length_serialized = length(utxos_hashes) |> VarInt.from_value()

    <<address::binary, validation_node_public_key::binary,
      length(previous_storage_nodes_public_keys)::8,
      :erlang.list_to_binary(previous_storage_nodes_public_keys)::binary,
      bit_size(chain_storage_nodes_view)::8, chain_storage_nodes_view::bitstring,
      bit_size(beacon_storage_nodes_view)::8, beacon_storage_nodes_view::bitstring,
      bit_size(io_storage_nodes_view)::8, io_storage_nodes_view::bitstring,
      utxos_hashes_length_serialized::binary, utxos_hashes_serialized::bitstring>>
  end

  defp deserialize_utxos_hashes(rest, acc, 0), do: {acc, rest}

  defp deserialize_utxos_hashes(<<hash::binary-size(32), rest::bitstring>>, acc, i) do
    # order doesnt matter
    deserialize_utxos_hashes(rest, [hash | acc], i - 1)
  end
end
