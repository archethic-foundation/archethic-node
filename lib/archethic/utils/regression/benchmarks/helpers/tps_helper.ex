defmodule ArchEthic.Utils.Regression.Benchmarks.Helpers.TPSHelper do
  @moduledoc """
  Helpers Methods to carry out the TPS benchmarks
  """

  def main() do
    recipient_address = "0000c084b09c60e3bde2d0a81df08b20d82d8b6dfc1d39bc3dfa5e41b731718f09e1"
    withdraw_uco_via_this_node(recipient_address)
  end

  def withdraw_uco_from_testnet_endpoint(recipient_address) do
    alias ArchEthic.Utils.Regression.Benchmarks.Helpers.FaucetEndpoint
    FaucetEndpoint.main(recipient_address)
  end

  def withdraw_uco_via_this_node(recipient_address) do
    alias ArchEthic.Utils.Regression.Benchmarks.Helpers.InternalFaucet
    InternalFaucet.main(recipient_address)
  end

  def withdraw_uco_via_host(recipient_address, host, port) do
    alias ArchEthic.Utils.Regression.Playbook
    Playbook.send_funds_to(recipient_address, host, port)
  end
end
