defmodule Uniris.Telemetry.Instrumenter do

  use Statix

  def setup do
    events = [
      [:uniris, :iplookup, :success],
      [:uniris, :iplookup, :failure]
    ]

    :telemetry.attach_many("uniris-telemetry-instrumenter", events, &handle_event/4, nil)
  end

  def handle_event([:uniris, :iplookup, :success], measurements, metadata, config) do
    # :ok = set("uniris.iplookup.success", "#{inspect config}")
    # :ok = Uniris.Telemetry.Instrumenter.increment("uniris.iplookup.count", 1, sample_rate: 1.0, tags: ["111", "222"])
  end
  def handle_event([:uniris, :iplookup, :failure], measurements, metadata, config) do
    # :ok = set("uniris.iplookup.failure", "#{inspect config}")
  end
end