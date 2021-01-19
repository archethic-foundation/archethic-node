defmodule Uniris.Telemetry.Instrumenter do

  import Telemetry.Metrics
  require Logger

  def setup do
    events = [
      [:uniris, :run_app, :success],
      [:uniris, :run_app, :failure]
    ]

    :telemetry.attach_many("uniris-telemetry-instrumenter", events, &handle_event/4, nil)
  end

  def polling_events do
    [
      last_value("vm.memory.binary", unit: :byte),
      counter("vm.memory.total")
    ]
  end

  def handle_event([:uniris, :run_app, :success], measurements, metadata, config) do
    Logger.debug "APP STARTED SUCCESSFULLY: #{inspect measurements}, #{inspect metadata}"
  end
  def handle_event([:uniris, :run_app, :failure], measurements, metadata, config) do
    Logger.debug "APP FAILED TO START: #{inspect measurements}, #{inspect metadata}"
  end
end 