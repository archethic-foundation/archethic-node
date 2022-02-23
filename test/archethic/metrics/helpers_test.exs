defmodule ArchEthic.Metrics.HelpersTest do
  use ExUnit.Case ,  async: true
  doctest ArchEthic.Metrics.Helpers
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!



end
