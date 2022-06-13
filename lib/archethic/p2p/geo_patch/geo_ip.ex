defmodule Archethic.P2P.GeoPatch.GeoIP do
  @moduledoc false

  alias __MODULE__.MaxMindDB

  use Knigge, otp_app: :archethic, default: MaxMindDB

  @callback get_coordinates(:inet.ip_address()) :: {latitude :: float(), longitude :: float()}
end
