defmodule Uniris.P2P.Node do
  @moduledoc """
  Describe an Uniris P2P node

  A geographical patch is computed from the IP based on a GeoIP lookup to get the coordinates.

  Each node by default are not authorized and become when a node shared secrets transaction involve it.
  Each node by default is not ready, and become it when a beacon pool receive a readyness message after the node bootstraping
  Each node by default has an average availability of 1 and decrease after beacon chain daily summary updates
  Each node by default is available and become unavailable when the messaging failed
  """

  require Logger

  alias Uniris.Crypto

  @enforce_keys [
    :first_public_key,
    :last_public_key,
    :ip,
    :port
  ]
  defstruct [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :network_patch,
    available?: true,
    average_availability: 1.0,
    availability_history: <<1::1>>,
    enrollment_date: nil,
    authorized?: false,
    ready?: false,
    ready_date: nil,
    authorization_date: nil
  ]

  @type t() :: %__MODULE__{
          first_public_key: Uniris.Crypto.key(),
          last_public_key: Uniris.Crypto.key(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          geo_patch: binary(),
          network_patch: binary(),
          available?: boolean(),
          average_availability: float(),
          availability_history: bitstring(),
          authorized?: boolean(),
          ready?: boolean(),
          enrollment_date: DateTime.t(),
          ready_date: DateTime.t(),
          authorization_date: DateTime.t()
        }

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

      iex> Uniris.P2P.Node.serialize(%Uniris.P2P.Node{
      ...>   first_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...>     92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
      ...>   last_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...>     92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   geo_patch: "FA9",
      ...>   network_patch: "AVC",
      ...>   available?: true,
      ...>   average_availability: 0.8,
      ...>   enrollment_date: ~U[2020-06-26 08:36:11Z],
      ...>   ready_date: ~U[2020-06-26 08:36:11Z],
      ...>   ready?: true,
      ...>   authorization_date: ~U[2020-06-26 08:36:11Z],
      ...>   authorized?: true
      ...> })
      <<
      # IP address
      127, 0, 0, 1,
      # Port
      11, 184,
      # Geo patch
      "FA9",
      # Network patch
      "AVC",
      # Avg availability
      80,
      # Enrollment date
      94, 245, 179, 123,
      # Available
      1::1,
      # Ready
      1::1,
      # Ready date
      94, 245, 179, 123,
      # Authorized
      1::1,
      # Authorization date
      94, 245, 179, 123,
      # First public key
      0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226,
      # Last public key
      0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226
      >>
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        geo_patch: geo_patch,
        network_patch: network_patch,
        average_availability: average_availability,
        enrollment_date: enrollment_date,
        available?: available?,
        ready?: ready?,
        ready_date: ready_date,
        authorized?: authorized?,
        authorization_date: authorization_date
      }) do
    ip_bin = <<o1, o2, o3, o4>>
    ready_bin = if ready?, do: 1, else: 0
    available_bin = if available?, do: 1, else: 0
    authorized_bin = if authorized?, do: 1, else: 0

    authorization_date =
      if authorization_date == nil, do: 0, else: DateTime.to_unix(authorization_date)

    ready_date = if ready_date == nil, do: 0, else: DateTime.to_unix(ready_date)
    avg_bin = trunc(average_availability * 100)

    <<ip_bin::binary-size(4), port::16, geo_patch::binary-size(3), network_patch::binary-size(3),
      avg_bin::8, DateTime.to_unix(enrollment_date)::32, available_bin::1, ready_bin::1,
      ready_date::32, authorized_bin::1, authorization_date::32, first_public_key::binary,
      last_public_key::binary>>
  end

  @doc """
  Deserialize an encoded node

  ## Examples

      iex> Uniris.P2P.Node.deserialize(<<
      ...> 127, 0, 0, 1, 11, 184, "FA9", "AVC", 80,
      ...> 94, 245, 179, 123, 1::1, 1::1, 94, 245, 179, 123,
      ...> 1::1, 94, 245, 179, 123,
      ...> 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...> 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226,
      ...> 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...> 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226
      ...> >>)
      {
        %Uniris.P2P.Node{
            first_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
              92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            last_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
              92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            ip: {127, 0, 0, 1},
            port: 3000,
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            ready_date: ~U[2020-06-26 08:36:11Z],
            ready?: true,
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {Uniris.P2P.Node.t(), bitstring}
  def deserialize(
        <<ip_bin::binary-size(4), port::16, geo_patch::binary-size(3),
          network_patch::binary-size(3), average_availability::8, enrollment_date::32,
          available::1, ready::1, ready_date::32, authorized::1, authorization_date::32,
          rest::bitstring>>
      ) do
    <<o1, o2, o3, o4>> = ip_bin
    available? = if available == 1, do: true, else: false
    ready? = if ready == 1, do: true, else: false
    authorized? = if authorized == 1, do: true, else: false

    ready_date = if ready_date == 0, do: nil, else: DateTime.from_unix!(ready_date)

    authorization_date =
      if authorization_date == 0, do: nil, else: DateTime.from_unix!(authorization_date)

    <<first_curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(first_curve_id)
    <<first_key::binary-size(key_size), last_curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(first_curve_id)
    <<last_key::binary-size(key_size), rest::bitstring>> = rest

    {
      %__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        geo_patch: geo_patch,
        network_patch: network_patch,
        average_availability: average_availability / 100,
        enrollment_date: DateTime.from_unix!(enrollment_date),
        available?: available?,
        ready?: ready?,
        authorized?: authorized?,
        ready_date: ready_date,
        authorization_date: authorization_date,
        first_public_key: <<first_curve_id::8>> <> first_key,
        last_public_key: <<last_curve_id::8>> <> last_key
      },
      rest
    }
  end
end
