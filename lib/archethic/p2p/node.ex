defmodule Archethic.P2P.Node do
  @moduledoc """
  Describe an Archethic P2P node

  Assumptions:
  - Each node by default is not authorized and become when a node shared secrets transaction involve it.
  - Each node by default is not available until the end of the node bootstrap or the next beacon chain daily summary updates
  - Each node by default has an average availability of 1 and decrease after beacon chain daily summary updates
  - Each node by default has a network equal to the geo patch, and is updated after each beacon chain daily summary updates
  """

  require Logger

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.NodeConfig

  alias Archethic.Utils

  defstruct [
    :first_public_key,
    :last_public_key,
    :mining_public_key,
    :last_address,
    :reward_address,
    :ip,
    :port,
    :http_port,
    :geo_patch,
    :network_patch,
    :enrollment_date,
    available?: false,
    synced?: false,
    average_availability: 1.0,
    authorized?: false,
    authorization_date: nil,
    transport: :tcp,
    origin_public_key: nil,
    last_update_date: ~U[2019-07-14 00:00:00Z],
    availability_update: ~U[2008-10-31 00:00:00Z]
  ]

  @type t() :: %__MODULE__{
          first_public_key: nil | Crypto.key(),
          last_public_key: Crypto.key(),
          mining_public_key: Crypto.key() | nil,
          last_address: nil | Crypto.key(),
          reward_address: nil | Crypto.key(),
          ip: nil | :inet.ip_address(),
          port: nil | :inet.port_number(),
          http_port: nil | :inet.port_number(),
          geo_patch: nil | binary(),
          network_patch: nil | binary(),
          available?: boolean(),
          synced?: boolean(),
          average_availability: float(),
          authorized?: boolean(),
          enrollment_date: nil | DateTime.t(),
          authorization_date: nil | DateTime.t(),
          transport: P2P.supported_transport(),
          last_update_date: DateTime.t(),
          availability_update: DateTime.t()
        }

  @doc """
  Encode node's transaction content
  """
  @spec encode_transaction_content(node_config :: NodeConfig.t()) :: binary()
  def encode_transaction_content(node_config) do
    NodeConfig.serialize(node_config)
  end

  @doc """
  Decode node information from transaction content
  """
  @spec decode_transaction_content(binary()) :: {:ok, NodeConfig.t()} | :error
  def decode_transaction_content(bin) do
    case NodeConfig.deserialize(bin) do
      {node_config, _rest} -> {:ok, node_config}
      :error -> :error
    end
  end

  @doc """
  Convert a tuple from NodeLedger to a Node instance
  """
  @spec cast(tuple()) :: t()
  def cast(
        {first_public_key, last_public_key, ip, port, http_port, geo_patch, network_patch,
         average_availability, enrollment_date, transport, reward_address, last_address,
         origin_public_key, synced?, last_update_date, available?, availability_update,
         mining_public_key}
      ) do
    %__MODULE__{
      ip: ip,
      port: port,
      http_port: http_port,
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      geo_patch: geo_patch,
      network_patch: network_patch,
      average_availability: average_availability,
      enrollment_date: enrollment_date,
      synced?: synced?,
      transport: transport,
      reward_address: reward_address,
      last_address: last_address,
      origin_public_key: origin_public_key,
      last_update_date: last_update_date,
      available?: available?,
      availability_update: availability_update,
      mining_public_key: mining_public_key
    }
  end

  @doc """
  Mark the node as authorized by including the authorization date

  ## Examples

      iex> Node.authorize(%Node{}, ~U[2020-09-10 07:50:58.466314Z])
      %Node{
        authorized?: true,
        authorization_date: ~U[2020-09-10 07:50:58.466314Z]
      }
  """
  @spec authorize(__MODULE__.t(), DateTime.t()) :: __MODULE__.t()
  def authorize(node = %__MODULE__{}, authorization_date = %DateTime{}) do
    %{node | authorized?: true, authorization_date: authorization_date}
  end

  @doc """
  Mark the node as non-authorized by including the authorization date

  ## Examples

      iex> Node.remove_authorization(%Node{
      ...>   authorized?: true,
      ...>   authorization_date: ~U[2020-09-10 07:50:58.466314Z]
      ...> })
      %Node{
        authorized?: false,
        authorization_date: nil
      }
  """
  @spec remove_authorization(__MODULE__.t()) :: __MODULE__.t()
  def remove_authorization(node = %__MODULE__{}) do
    %{node | authorized?: false, authorization_date: nil}
  end

  @doc """
  Get the numerical value of the network patch hexadecimal
  """
  @spec get_network_patch_num(__MODULE__.t()) :: non_neg_integer()
  def get_network_patch_num(%__MODULE__{network_patch: patch}) do
    patch
    |> String.to_charlist()
    |> List.to_integer(16)
  end

  @doc """
  Define the roll as enrolled with the first transaction time and initialize the network patch
  with the geographical patch

  ## Examples

      iex> Node.enroll(%Node{geo_patch: "AAA"}, ~U[2020-09-10 07:50:58.466314Z])
      %Node{
        enrollment_date: ~U[2020-09-10 07:50:58.466314Z],
        geo_patch: "AAA",
        network_patch: "AAA"
      }
  """
  @spec enroll(__MODULE__.t(), date :: DateTime.t()) :: __MODULE__.t()
  def enroll(node = %__MODULE__{geo_patch: geo_patch}, date = %DateTime{}) do
    %{node | enrollment_date: date, network_patch: geo_patch}
  end

  @doc """
  Serialize a node into binary format
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        http_port: http_port,
        transport: transport,
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        mining_public_key: mining_public_key,
        geo_patch: geo_patch,
        network_patch: network_patch,
        average_availability: average_availability,
        enrollment_date: enrollment_date,
        available?: available?,
        synced?: synced?,
        authorized?: authorized?,
        authorization_date: authorization_date,
        reward_address: reward_address,
        last_address: last_address,
        origin_public_key: origin_public_key,
        last_update_date: last_update_date,
        availability_update: availability_update
      }) do
    ip_bin = <<o1, o2, o3, o4>>
    available_bin = if available?, do: 1, else: 0
    synced_bin = if synced?, do: 1, else: 0
    authorized_bin = if authorized?, do: 1, else: 0

    authorization_date =
      if authorization_date == nil, do: 0, else: DateTime.to_unix(authorization_date)

    avg_bin = trunc(average_availability * 100)

    mining_public_key_bin =
      if is_nil(mining_public_key),
        do: <<0::8>>,
        else: <<1::8, mining_public_key::binary>>

    <<ip_bin::binary-size(4), port::16, http_port::16, serialize_transport(transport)::8,
      geo_patch::binary-size(3), network_patch::binary-size(3), avg_bin::8,
      DateTime.to_unix(enrollment_date)::32, available_bin::1, synced_bin::1, authorized_bin::1,
      authorization_date::32, first_public_key::binary, last_public_key::binary,
      reward_address::binary, last_address::binary, origin_public_key::binary,
      DateTime.to_unix(last_update_date)::32, DateTime.to_unix(availability_update)::32,
      mining_public_key_bin::binary>>
  end

  defp serialize_transport(MockTransport), do: 0
  defp serialize_transport(:tcp), do: 1

  @doc """
  Deserialize an encoded node

  """
  @spec deserialize(bitstring()) :: {Archethic.P2P.Node.t(), bitstring}
  def deserialize(
        <<ip_bin::binary-size(4), port::16, http_port::16, transport::8,
          geo_patch::binary-size(3), network_patch::binary-size(3), average_availability::8,
          enrollment_date::32, available::1, synced::1, authorized::1, authorization_date::32,
          rest::bitstring>>
      ) do
    <<o1, o2, o3, o4>> = ip_bin
    available? = if available == 1, do: true, else: false
    synced? = if synced == 1, do: true, else: false
    authorized? = if authorized == 1, do: true, else: false

    authorization_date =
      if authorization_date == 0, do: nil, else: DateTime.from_unix!(authorization_date)

    {first_public_key, rest} = Utils.deserialize_public_key(rest)
    {last_public_key, rest} = Utils.deserialize_public_key(rest)
    {reward_address, rest} = Utils.deserialize_address(rest)
    {last_address, rest} = Utils.deserialize_address(rest)

    {origin_public_key, <<last_update_date::32, availability_update::32, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {mining_public_key, rest} =
      case rest do
        <<1::8, rest::bitstring>> -> Utils.deserialize_public_key(rest)
        <<0::8, rest::bitstring>> -> {nil, rest}
      end

    {
      %__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        http_port: http_port,
        transport: deserialize_transport(transport),
        geo_patch: geo_patch,
        network_patch: network_patch,
        average_availability: average_availability / 100,
        enrollment_date: DateTime.from_unix!(enrollment_date),
        available?: available?,
        synced?: synced?,
        authorized?: authorized?,
        authorization_date: authorization_date,
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        reward_address: reward_address,
        last_address: last_address,
        origin_public_key: origin_public_key,
        last_update_date: DateTime.from_unix!(last_update_date),
        availability_update: DateTime.from_unix!(availability_update),
        mining_public_key: mining_public_key
      },
      rest
    }
  end

  defp deserialize_transport(0), do: MockTransport
  defp deserialize_transport(1), do: :tcp

  @doc """
  Return the node's endpoint stringified
  """
  @spec endpoint(t()) :: binary()
  def endpoint(%__MODULE__{ip: ip, port: port}), do: "#{:inet.ntoa(ip)}:#{port}"
end
