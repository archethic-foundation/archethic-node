defmodule Archethic.Networking.IPLookupTest do
  @moduledoc false
  use ExUnit.Case, async: false
  import Mox
  import Archethic.Networking.IPLookup, only: [get_node_ip: 0]

  alias Archethic.Networking.IPLookup.LocalDiscovery
  alias Archethic.Networking.IPLookup.RemoteDiscovery

  describe "In Dev mode: get_node_ip()/0" do
    Mix.env(:test)
    assert :test == Mix.env()
    Mix.env(:dev)
    assert :dev == Mix.env()

    test "Static IP Should not be Validated to be a Public IP| Must Return Static IP" do
      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      assert {127, 0, 0, 1} == get_node_ip()
    end

    test "Localdiscovery/NAT & RemoteDiscovery/IPIFY " do
      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      assert {127, 0, 0, 1} == get_node_ip()
    end

    test "assert currnet config is :dev  & restore to :test" do
      assert :dev == Mix.env()
      Mix.env(:test)
      assert :test == Mix.env()
    end
  end

  describe "In Prod mode: get_node_ip()/0" do
    test "assert current config is test  & changed to :prod" do
      Mix.env(:test)
      assert :test == Mix.env()
      Mix.env(:prod)
      assert :prod == Mix.env()
    end

    test "If Static IP, it must raise an error" do
      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        MockStatic,
        persistent: false
      )

      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      provider = MockStatic

      reason = :invalid_ip

      assert_raise RuntimeError,
                   "Cannot use #{provider} IP lookup - #{inspect(reason)}",
                   fn -> get_node_ip() end
    end

    test "Private IP(NAT), it must fallback to IPIFY to get public IP" do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        LocalDiscovery,
        persistent: false
      )

      MockNAT
      |> expect(:get_node_ip, fn -> {:ok, {0, 0, 0, 0}} end)

      MockIPIFY
      |> expect(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end

    test "IPIFIY IP: returns public IP" do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        RemoteDiscovery,
        persistent: false
      )

      MockIPIFY
      |> expect(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end

    test "assert currnet config is :prod & restore to :test" do
      assert :prod == Mix.env()
      Mix.env(:test)
      assert :test == Mix.env()
    end
  end
end
