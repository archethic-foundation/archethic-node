defmodule Archethic.P2P.NodeConfig do
  @moduledoc """
  Configuration of the node in the network.
  It contains P2P informations, reward address, mining public key and origin.
  """

  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.Utils

  defstruct [
    :first_public_key,
    :ip,
    :port,
    :http_port,
    :transport,
    :reward_address,
    :origin_public_key,
    :origin_certificate,
    :mining_public_key,
    :geo_patch
  ]

  @type t :: %__MODULE__{
          first_public_key: nil | Crypto.key(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          http_port: :inet.port_number(),
          transport: P2P.supported_transport(),
          reward_address: Crypto.prepended_hash(),
          origin_public_key: Crypto.key(),
          origin_certificate: nil | binary(),
          mining_public_key: nil | Crypto.key(),
          geo_patch: nil | binary()
        }

  @doc """
  Extract the informations from the Node struct and return a NodeConfig
  """
  @spec from_node(node :: Node.t()) :: t()
  def from_node(%Node{
        first_public_key: first_public_key,
        ip: ip,
        port: port,
        http_port: http_port,
        transport: transport,
        reward_address: reward_address,
        origin_public_key: origin_public_key,
        mining_public_key: mining_public_key,
        geo_patch: geo_patch
      }) do
    %__MODULE__{
      first_public_key: first_public_key,
      ip: ip,
      port: port,
      http_port: http_port,
      transport: transport,
      reward_address: reward_address,
      origin_public_key: origin_public_key,
      mining_public_key: mining_public_key,
      geo_patch: geo_patch
    }
  end

  @doc """
  Returns true if the config are different
  do not compare origin certificate
  """
  @spec different?(config1 :: t(), config2 :: t()) :: boolean()
  def different?(config1, config2) do
    config1 = %__MODULE__{config1 | origin_certificate: nil}
    config2 = %__MODULE__{config2 | origin_certificate: nil}

    config1 != config2
  end

  @doc """
  Serialize a config in binary.
  Origin certificate should not be nil
  """
  @spec serialize(node_config :: t()) :: binary()
  def serialize(%__MODULE__{
        ip: {ip1, ip2, ip3, ip4},
        port: port,
        http_port: http_port,
        transport: transport,
        reward_address: reward_address,
        origin_public_key: origin_public_key,
        origin_certificate: origin_certificate,
        mining_public_key: mining_public_key,
        geo_patch: geo_patch
      })
      when origin_certificate != nil do
    <<ip1, ip2, ip3, ip4, port::16, http_port::16, serialize_transport(transport)::8,
      reward_address::binary, origin_public_key::binary, byte_size(origin_certificate)::16,
      origin_certificate::binary, mining_public_key::binary, geo_patch::binary-size(3)>>
  end

  defp serialize_transport(MockTransport), do: 0
  defp serialize_transport(:tcp), do: 1

  @doc """
  Deserialize a binary and return a NodeConfig
  """

  @spec deserialize(binary()) :: {t(), binary()} | :error
  def deserialize(<<ip::binary-size(4), port::16, http_port::16, transport::8, rest::binary>>) do
    with <<ip1, ip2, ip3, ip4>> <- ip,
         {reward_address, rest} <- Utils.deserialize_address(rest),
         {origin_public_key, rest} <- Utils.deserialize_public_key(rest),
         <<origin_certificate_size::16, origin_certificate::binary-size(origin_certificate_size),
           rest::binary>> <- rest,
         {mining_public_key, rest} <- extract_mining_public_key(rest),
         {geo_patch, rest} <- extract_geo_patch(rest) do
      node_config = %__MODULE__{
        ip: {ip1, ip2, ip3, ip4},
        port: port,
        http_port: http_port,
        transport: deserialize_transport(transport),
        reward_address: reward_address,
        origin_public_key: origin_public_key,
        origin_certificate: origin_certificate,
        mining_public_key: mining_public_key,
        geo_patch: geo_patch
      }

      {node_config, rest}
    else
      _ -> :error
    end
  end

  def deserialize(_), do: :error

  defp deserialize_transport(0), do: MockTransport
  defp deserialize_transport(1), do: :tcp

  defp extract_mining_public_key(<<>>), do: {nil, <<>>}
  defp extract_mining_public_key(rest), do: Utils.deserialize_public_key(rest)

  defp extract_geo_patch(<<geo_patch::binary-size(3), rest::binary>>), do: {geo_patch, rest}
  defp extract_geo_patch(rest), do: {nil, rest}
end
