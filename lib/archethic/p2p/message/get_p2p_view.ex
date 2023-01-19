defmodule Archethic.P2P.Message.GetP2PView do
  @moduledoc """
  Represents a request to get the P2P view from a list of nodes
  """
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Message.P2PView
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  defstruct [:node_public_keys]

  @type t :: %__MODULE__{
          node_public_keys: list(Crypto.key())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: P2PView.t()
  def process(%__MODULE__{node_public_keys: node_public_keys}, _) do
    nodes =
      Enum.map(node_public_keys, fn key ->
        {:ok, node} = P2P.get_node_info(key)
        node
      end)

    view = P2P.nodes_availability_as_bits(nodes)
    %P2PView{nodes_view: view}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{node_public_keys: node_public_keys}) do
    encoded_node_public_keys_length =
      length(node_public_keys)
      |> VarInt.from_value()

    <<encoded_node_public_keys_length::binary, :erlang.list_to_binary(node_public_keys)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_node_public_keys, rest} = rest |> VarInt.get_value()
    {public_keys, rest} = Utils.deserialize_public_key_list(rest, nb_node_public_keys, [])
    {%__MODULE__{node_public_keys: public_keys}, rest}
  end
end
