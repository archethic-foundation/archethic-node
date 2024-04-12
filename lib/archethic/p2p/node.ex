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

  alias Archethic.Utils

  defstruct [
    :first_public_key,
    :last_public_key,
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

  @doc """
  Decode node information from transaction content

  ## Examples

      iex> Node.decode_transaction_content(
      ...>   <<127, 0, 0, 1, 11, 184, 15, 160, 1, 0, 0, 173, 179, 246, 126, 247, 223, 20, 86, 201,
      ...>     55, 190, 29, 59, 212, 196, 36, 89, 178, 185, 211, 23, 68, 30, 22, 75, 39, 197, 8,
      ...>     186, 167, 123, 182, 0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166,
      ...>     95, 250, 255, 90, 210, 227, 150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221,
      ...>     196, 169, 0, 64, 63, 40, 158, 160, 56, 156, 206, 193, 107, 50, 250, 244, 6, 212, 171,
      ...>     158, 240, 175, 162, 2, 55, 86, 26, 215, 44, 61, 198, 143, 141, 22, 122, 16, 89, 155,
      ...>     28, 132, 231, 22, 143, 53, 126, 102, 148, 210, 88, 103, 216, 37, 175, 164, 87, 10,
      ...>     255, 229, 33, 178, 204, 184, 228, 130, 173, 148, 82, 126>>
      ...> )
      {:ok, {127, 0, 0, 1}, 3000, 4000, :tcp,
       <<0, 0, 173, 179, 246, 126, 247, 223, 20, 86, 201, 55, 190, 29, 59, 212, 196, 36, 89, 178,
         185, 211, 23, 68, 30, 22, 75, 39, 197, 8, 186, 167, 123, 182>>,
       <<0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90, 210, 227,
         150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221, 196, 169>>,
       <<63, 40, 158, 160, 56, 156, 206, 193, 107, 50, 250, 244, 6, 212, 171, 158, 240, 175, 162, 2,
         55, 86, 26, 215, 44, 61, 198, 143, 141, 22, 122, 16, 89, 155, 28, 132, 231, 22, 143, 53,
         126, 102, 148, 210, 88, 103, 216, 37, 175, 164, 87, 10, 255, 229, 33, 178, 204, 184, 228,
         130, 173, 148, 82, 126>>}
  """
  @spec decode_transaction_content(binary()) ::
          {:ok, ip_address :: :inet.ip_address(), p2p_port :: :inet.port_number(),
           http_port :: :inet.port_number(), P2P.supported_transport(),
           reward_address :: binary(), origin_public_key :: Crypto.key(),
           key_certificate :: binary()}
          | :error
  def decode_transaction_content(
        <<ip::binary-size(4), port::16, http_port::16, transport::8, rest::binary>>
      ) do
    with <<ip0, ip1, ip2, ip3>> <- ip,
         {reward_address, rest} <- Utils.deserialize_address(rest),
         {origin_public_key, rest} <- Utils.deserialize_public_key(rest),
         <<key_certificate_size::16, key_certificate::binary-size(key_certificate_size),
           _::binary>> <- rest do
      {:ok, {ip0, ip1, ip2, ip3}, port, http_port, deserialize_transport(transport),
       reward_address, origin_public_key, key_certificate}
    else
      _ ->
        :error
    end
  end

  def decode_transaction_content(<<>>), do: :error

  @doc """
  Encode node's transaction content

  ## Examples

      iex> Node.encode_transaction_content(
      ...>   {127, 0, 0, 1},
      ...>   3000,
      ...>   4000,
      ...>   :tcp,
      ...>   <<0, 0, 173, 179, 246, 126, 247, 223, 20, 86, 201, 55, 190, 29, 59, 212, 196, 36, 89,
      ...>     178, 185, 211, 23, 68, 30, 22, 75, 39, 197, 8, 186, 167, 123, 182>>,
      ...>   <<0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90, 210,
      ...>     227, 150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221, 196, 169>>,
      ...>   <<63, 40, 158, 160, 56, 156, 206, 193, 107, 50, 250, 244, 6, 212, 171, 158, 240, 175,
      ...>     162, 2, 55, 86, 26, 215, 44, 61, 198, 143, 141, 22, 122, 16, 89, 155, 28, 132, 231,
      ...>     22, 143, 53, 126, 102, 148, 210, 88, 103, 216, 37, 175, 164, 87, 10, 255, 229, 33,
      ...>     178, 204, 184, 228, 130, 173, 148, 82, 126>>
      ...> )
      <<127, 0, 0, 1, 11, 184, 15, 160, 1, 0, 0, 173, 179, 246, 126, 247, 223, 20, 86, 201, 55, 190,
        29, 59, 212, 196, 36, 89, 178, 185, 211, 23, 68, 30, 22, 75, 39, 197, 8, 186, 167, 123, 182,
        0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90, 210, 227,
        150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221, 196, 169, 0, 64, 63, 40, 158, 160,
        56, 156, 206, 193, 107, 50, 250, 244, 6, 212, 171, 158, 240, 175, 162, 2, 55, 86, 26, 215,
        44, 61, 198, 143, 141, 22, 122, 16, 89, 155, 28, 132, 231, 22, 143, 53, 126, 102, 148, 210,
        88, 103, 216, 37, 175, 164, 87, 10, 255, 229, 33, 178, 204, 184, 228, 130, 173, 148, 82,
        126>>
  """
  @spec encode_transaction_content(
          :inet.ip_address(),
          :inet.port_number(),
          :inet.port_number(),
          P2P.supported_transport(),
          reward_address :: binary(),
          origin_public_key :: Crypto.key(),
          origin_key_certificate :: binary()
        ) :: binary()
  def encode_transaction_content(
        {ip1, ip2, ip3, ip4},
        port,
        http_port,
        transport,
        reward_address,
        origin_public_key,
        key_certificate
      ) do
    <<ip1, ip2, ip3, ip4, port::16, http_port::16, serialize_transport(transport)::8,
      reward_address::binary, origin_public_key::binary, byte_size(key_certificate)::16,
      key_certificate::binary>>
  end

  @type t() :: %__MODULE__{
          first_public_key: nil | Crypto.key(),
          last_public_key: Crypto.key(),
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
  Convert a tuple from NodeLedger to a Node instance
  """
  @spec cast(tuple()) :: __MODULE__.t()
  def cast(
        {first_public_key, last_public_key, ip, port, http_port, geo_patch, network_patch,
         average_availability, enrollment_date, transport, reward_address, last_address,
         origin_public_key, synced?, last_update_date, available?, availability_update}
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
      availability_update: availability_update
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

  # defp new_average_availability(history) do
  #   list = for <<view::1 <- history>>, do: view

  #   list
  #   |> Enum.frequencies()
  #   |> Map.get(1)
  #   |> case do
  #     nil ->
  #       0.0

  #     available_times ->
  #       Float.floor(available_times / bit_size(history), 1)
  #   end
  # end

  @doc """
  Serialize a node into binary format

  ## Examples

      iex> Node.serialize(%Node{
      ...>   first_public_key:
      ...>     <<0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...>       92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
      ...>   last_public_key:
      ...>     <<0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...>       92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   http_port: 4000,
      ...>   transport: :tcp,
      ...>   geo_patch: "FA9",
      ...>   network_patch: "AVC",
      ...>   available?: true,
      ...>   synced?: true,
      ...>   average_availability: 0.8,
      ...>   enrollment_date: ~U[2020-06-26 08:36:11Z],
      ...>   authorization_date: ~U[2020-06-26 08:36:11Z],
      ...>   last_update_date: ~U[2020-06-26 08:36:11Z],
      ...>   availability_update: ~U[2020-06-26 08:36:11Z],
      ...>   authorized?: true,
      ...>   reward_address:
      ...>     <<0, 0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17,
      ...>       182, 87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
      ...>   last_address:
      ...>     <<0, 0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32,
      ...>       173, 88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
      ...>   origin_public_key:
      ...>     <<0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90,
      ...>       210, 227, 150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221, 196, 169>>
      ...> })
      <<127, 0, 0, 1, 11, 184, 15, 160, 1, "FA9", "AVC", 80, 94, 245, 179, 123, 1::1, 1::1, 1::1,
        94, 245, 179, 123, 0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249,
        247, 86, 64, 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226, 0, 0,
        182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92, 224, 91,
        182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226, 0, 0, 163, 237, 233, 93, 14,
        241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182, 87, 9, 7, 53, 146, 174, 125, 5, 244,
        42, 35, 209, 142, 24, 164, 0, 0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173,
        254, 94, 179, 32, 173, 88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112,
        0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90, 210, 227,
        150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221, 196, 169, 94, 245, 179, 123, 94, 245,
        179, 123>>
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        http_port: http_port,
        transport: transport,
        first_public_key: first_public_key,
        last_public_key: last_public_key,
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

    <<ip_bin::binary-size(4), port::16, http_port::16, serialize_transport(transport)::8,
      geo_patch::binary-size(3), network_patch::binary-size(3), avg_bin::8,
      DateTime.to_unix(enrollment_date)::32, available_bin::1, synced_bin::1, authorized_bin::1,
      authorization_date::32, first_public_key::binary, last_public_key::binary,
      reward_address::binary, last_address::binary, origin_public_key::binary,
      DateTime.to_unix(last_update_date)::32, DateTime.to_unix(availability_update)::32>>
  end

  defp serialize_transport(MockTransport), do: 0
  defp serialize_transport(:tcp), do: 1

  @doc """
  Deserialize an encoded node

  ## Examples

      iex> Node.deserialize(
      ...>   <<127, 0, 0, 1, 11, 184, 15, 160, 1, "FA9", "AVC", 80, 94, 245, 179, 123, 1::1, 1::1,
      ...>     1::1, 94, 245, 179, 123, 0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159,
      ...>     209, 249, 247, 86, 64, 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57,
      ...>     250, 59, 226, 0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249,
      ...>     247, 86, 64, 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59,
      ...>     226, 0, 0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17,
      ...>     182, 87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164, 0, 0, 165, 32,
      ...>     187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173, 88, 122, 234,
      ...>     88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112, 0, 0, 130, 83, 96, 217, 99,
      ...>     234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90, 210, 227, 150, 117, 26, 64, 143,
      ...>     55, 199, 95, 222, 35, 137, 221, 196, 169, 94, 245, 179, 123, 94, 245, 179, 123>>
      ...> )
      {
        %Node{
          first_public_key:
            <<0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92,
              224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
          last_public_key:
            <<0, 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64, 92,
              224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
          ip: {127, 0, 0, 1},
          port: 3000,
          http_port: 4000,
          transport: :tcp,
          geo_patch: "FA9",
          network_patch: "AVC",
          available?: true,
          synced?: true,
          average_availability: 0.8,
          enrollment_date: ~U[2020-06-26 08:36:11Z],
          authorization_date: ~U[2020-06-26 08:36:11Z],
          last_update_date: ~U[2020-06-26 08:36:11Z],
          availability_update: ~U[2020-06-26 08:36:11Z],
          authorized?: true,
          reward_address:
            <<0, 0, 163, 237, 233, 93, 14, 241, 241, 8, 144, 218, 105, 16, 138, 243, 223, 17, 182,
              87, 9, 7, 53, 146, 174, 125, 5, 244, 42, 35, 209, 142, 24, 164>>,
          last_address:
            <<0, 0, 165, 32, 187, 102, 112, 133, 38, 17, 232, 54, 228, 173, 254, 94, 179, 32, 173,
              88, 122, 234, 88, 139, 82, 26, 113, 42, 8, 183, 190, 163, 221, 112>>,
          origin_public_key:
            <<0, 0, 130, 83, 96, 217, 99, 234, 242, 235, 175, 236, 109, 166, 95, 250, 255, 90, 210,
              227, 150, 117, 26, 64, 143, 55, 199, 95, 222, 35, 137, 221, 196, 169>>
        },
        ""
      }
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
        availability_update: DateTime.from_unix!(availability_update)
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
