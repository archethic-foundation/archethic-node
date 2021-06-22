defmodule Uniris.P2P.GeoPatch.GeoIP do
  @moduledoc false

  alias __MODULE__.IP2LocationImpl

  use Knigge, otp_app: :uniris, default: IP2LocationImpl

  @callback get_coordinates(:inet.ip_address()) :: {latitude :: float(), longitude :: float()}
end
