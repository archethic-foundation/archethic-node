defmodule Archethic.Networking.IPLookupTest do
  @moduledoc false
  use ExUnit.Case, async: false
  import Mox
  import Archethic.Networking.IPLookup, only: [get_node_ip: 0]

  def put_conf(validate_node_ip: validate_node_ip, mock_module: mock_module) do
    Application.put_env(
      :archethic,
      Archethic.Networking,
      validate_node_ip: validate_node_ip,
      persistent: false
    )

    Application.put_env(
      :archethic,
      Archethic.Networking.IPLookup,
      mock_module,
      persistent: false
    )
  end

  describe "get_node_ip()/0" do
    test "Dev-mode:  Static IP Should not be Validated to be a Public IP" do
      put_conf(validate_node_ip: false, mock_module: MockStatic)

      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      assert {127, 0, 0, 1} == get_node_ip()
    end

    test "Prod-mode: If Static IP, raise error " do
      # set prod mode configuration values
      put_conf(validate_node_ip: true, mock_module: MockStatic)

      MockStatic
      |> expect(:get_node_ip, fn -> {:ok, {127, 0, 0, 1}} end)

      get_node_ip()

      assert_raise(RuntimeError, ~r/Cannot use \w\.\w IP lookup - :invalid_ip/)
    end

    test "Prod-mode: Private IP(NAT), it must fallback to IPIFY to get public IP" do
      # set prod mode configuration values
      put_conf(validate_node_ip: true, mock_module: MockNAT)

      MockNAT
      |> expect(:get_node_ip, fn -> {:ok, {0, 0, 0, 0}} end)

      MockPublicGateway
      |> expect(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end

    test "IPIFIY IP: returns public IP" do
      # set prod mode configuration values
      put_conf(validate_node_ip: true, mock_module: MockPublicGateway)

      MockPublicGateway
      |> expect(:get_node_ip, fn -> {:ok, {17, 5, 7, 8}} end)

      assert {17, 5, 7, 8} == get_node_ip()
    end
  end
end
