defmodule ArchEthic.NetworkingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ArchEthic.Networking

  doctest ArchEthic.Networking

  describe "valid_ip?/1" do
    property "should return false for loopback address range" do
      ip_generator = tuple({constant(127), integer(0..255), integer(0..255), integer(0..255)})

      check all(ip <- ip_generator) do
        refute Networking.valid_ip?(ip)
      end
    end

    property "should return false for Class A private address range" do
      ip_generator = tuple({constant(10), integer(0..255), integer(0..255), integer(0..255)})

      check all(ip <- ip_generator) do
        refute Networking.valid_ip?(ip)
      end
    end

    property "should return false for Class B private address range" do
      ip_generator = tuple({constant(172), integer(16..31), integer(0..255), integer(0..255)})

      check all(ip <- ip_generator) do
        refute Networking.valid_ip?(ip)
      end
    end

    property "should return false for Class C private address range" do
      ip_generator = tuple({constant(192), constant(168), integer(0..255), integer(0..255)})

      check all(ip <- ip_generator) do
        refute Networking.valid_ip?(ip)
      end
    end
  end
end
