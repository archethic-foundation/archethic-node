defmodule Archethic.Networking.IPLookupTest do
  @moduledoc false
  use ExUnit.Case
  import Mox
  import Archethic.Networking.IPLookup, only: [get_node_ip: 0]

  describe "get_node_ip()/0" do
    test "Dev-mode:  Static IP Should not be Validated to be a Public IP" do
      # set dev mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: false
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        provider: MockStatic,
        persistent: false
      )

      MockStatic
      |> stub(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      assert {127, 0, 0, 1} == get_node_ip()
    end

    test "Prod-mode: If Static IP, it must fallback to IPIFY to get public IP " do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: true
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        provider: MockStatic,
        persistent: false
      )

      MockStatic
      |> stub(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      MockIPIFY
      |> stub(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end

    test "Prod-mode: Private IP(NAT), it must fallback to IPIFY to get public IP" do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: true
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        provider: MockNAT,
        persistent: false
      )

      MockNAT
      |> stub(:get_node_ip, fn -> {:ok, {0, 0, 0, 0}} end)

      MockIPIFY
      |> stub(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end

    test "IPIFIY IP: returns public IP" do
      # set prod mode configuration values
      Application.put_env(
        :archethic,
        Archethic.Networking,
        validate_node_ip: true
      )

      Application.put_env(
        :archethic,
        Archethic.Networking.IPLookup,
        provider: MockIPIFY,
        persistent: false
      )

      MockIPIFY
      |> stub(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end
  end
end
