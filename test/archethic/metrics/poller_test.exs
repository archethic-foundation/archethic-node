defmodule ArchEthic.Metrics.Pollers_test do
  use ExUnit.Case, async: true
  alias ArchEthic.Metrics.Poller

  # describe "" do
  #   test "Listless.list/0 returns an empty list" do
  #     {:ok, pid} = start_supervised(ArchEthic.Metrics.Poller)
  #   end
  # end
end

# function of poller:
# initialization
# default state
# periodic_metric_aggregation
# monitor live view procces & store there pid
# live view proces down
# periodic_calculation_of_points
# get new data

#  testing guidlines :operation and state
#  use of dynamic data rather than using the static data
#  use of pin operator for that--
#  check for the  core logic/concept  is working or not
#  tests should work even if we change the internal state representation or either code
#  move all the pure data structure logic to other modules
