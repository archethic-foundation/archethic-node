defmodule UnirisNetwork.Node do
  @enforce_keys [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :availability,
    :average_availability
  ]
  defstruct [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :network_patch,
    :availability,
    :average_availability
  ]

  @type patch() :: {0..9 | ?A..?F, 0..9 | ?A..?F, 0..9 | ?A..?F}

  @type t() :: %__MODULE__{
          first_public_key: binary(),
          last_public_key: binary(),
          ip: :inet.ip_address(),
          port: :inet.port_number(),
          geo_patch: patch(),
          network_patch: patch(),
          availability: boolean(),
          average_availability: float()
        }

  def new(first_public_key: first_public_key, ip: ip, port: port)
      when is_binary(first_public_key) and is_integer(ip) and is_integer(port) do
    %__MODULE__{
      first_public_key: first_public_key,
      last_public_key: first_public_key,
      ip: ip,
      port: port,
      geo_patch: UnirisNetwork.GeoPatch.from_ip(ip),
      availability: 1,
      average_availability: 0
    }
  end
end
