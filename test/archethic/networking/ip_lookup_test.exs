defmodule Archethic.Networking.IPLookupTest do
  @moduledoc false
  use ExUnit.Case
  import Mox

  alias Archethic.Networking.IPLookup.IPIFY
  alias Archethic.Networking.IPLookup.NAT
  alias Archethic.Networking.IPLookup.Static
  alias Archethic.Networking.IPLookup

  describe "get_node_ip()/0" do
    test "In Development mode Static IP Should not be Validated to be a Public IP" do
      # set dev mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: false
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        MockStatic,
        persistent: false
      )

      MockStatic
      |> stub(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      assert {127, 0, 0, 1} == IPLookup.get_node_ip()
    end

    test "In Prod mode , if IP is Static , It must fallback to IPIFY to get public IP " do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: true
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        MockStatic,
        persistent: false
      )

      MockStatic
      |> stub(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      MockIPIFY
      |> stub(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == IPLookup.get_node_ip()
    end

    test "In Prod mode , if IP is a Private IP(NAT) , It must fallback to IPIFY to get public IP  " do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: true
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        MockNAT,
        persistent: false
      )

      MockNAT
      |> stub(:get_node_ip, fn -> {:ok, {0, 0, 0, 0}} end)

      MockIPIFY
      |> stub(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == IPLookup.get_node_ip()
    end

    test "IPIFIY IP " do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: true
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        MockIPIFY,
        persistent: false
      )

      MockIPIFY
      |> stub(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == IPLookup.get_node_ip()
    end
  end
end
