defmodule Archethic.Networking.IPLookupTest do
  @moduledoc false
  use ExUnit.Case, async: false
  import Mox
  import Archethic.Networking.IPLookup, only: [get_node_ip: 0]

  alias Archethic.Networking.IPLookup.LocalDiscovery
  alias Archethic.Networking.IPLookup.RemoteDiscovery

  def put_conf(validate_node_ip: validate_node_ip, ip_provider: ip_provider) do
    Application.put_env(
      :archethic,
      Archethic.Networking,
      validate_node_ip: validate_node_ip
    )

    Application.put_env(
      :archethic,
      Archethic.Networking.IPLookup,
      ip_provider,
      persistent: false
    )
  end

  describe("Mix.env() as :dev, Archethic.Networking.IPLookup.get_node_ip()/0 ") do
    # During mix.env as :dev we should not use NAT//IPIFY
    test "Dev-mode:  Static IP Should not be Validated to be a Public IP" do
      put_conf(validate_node_ip: false, ip_provider: MockStatic)

      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      assert {127, 0, 0, 1} == get_node_ip()
    end
  end

  describe "Mix.env() as :prod, Archethic.Networking.IPLookup.get_node_ip()/0" do
    test "If Static IP, it must raise an error " do
      # set prod mode configuration values
      put_conf(validate_node_ip: true, ip_provider: MockStatic)

      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      provider = MockStatic
      reason = :invalid_ip

      assert_raise(RuntimeError, "Cannot use #{provider} IP lookup - #{inspect(reason)}", fn ->
        get_node_ip()
      end)
    end

    test "If Private IP(NAT), it must fallback to IPIFY to get public IP" do
      # set prod mode configuration values
      put_conf(validate_node_ip: true, ip_provider: LocalDiscovery)

      MockNAT
      |> expect(:get_node_ip, fn -> {:ok, {0, 0, 0, 0}} end)

      MockIPIFY
      |> expect(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end

    test "IPIFIY IP: returns public IP" do
      # set prod mode configuration values
      put_conf(validate_node_ip: true, ip_provider: RemoteDiscovery)

      MockIPIFY
      |> expect(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end
  end
end
