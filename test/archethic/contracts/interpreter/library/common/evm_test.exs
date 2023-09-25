defmodule Archethic.Contracts.Interpreter.Library.Common.EvmTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Evm

  describe "abi_encode/2" do
    test "should encode abi with only types" do
      expected_data =
        Base.encode16(
          <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 69, 116, 104, 101, 114, 32, 84, 111, 107, 101, 110,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
          case: :lower
        )

      assert expected_data == Evm.abi_encode("(string)", ["Ether Token"])

      expected_data =
        Base.encode16(
          <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 132, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 69, 116, 104, 101, 114, 32, 84, 111,
            107, 101, 110, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
          case: :lower
        )

      assert expected_data == Evm.abi_encode("(uint, string)", [132, "Ether Token"])

      assert expected_data == Evm.abi_encode("(int, string)", [132, "Ether Token"])
    end

    test "should encode abi with only function name" do
      assert "722713f7" == Evm.abi_encode("balanceOf()")
    end

    test "should encode abi with function and args" do
      address = "0xF742d4cE7713c54dD701AA9e92101aC42D63F895"

      assert "70a08231000000000000000000000000f742d4ce7713c54dd701aa9e92101ac42d63f895" ==
               Evm.abi_encode("balanceOf(address)", [address])
    end

    test "should encode abi should remove 0x" do
      address_0x = "0xF742d4cE7713c54dD701AA9e92101aC42D63F895"
      address_flat = "F742d4cE7713c54dD701AA9e92101aC42D63F895"

      assert Evm.abi_encode("balanceOf(address)", [address_0x]) ==
               Evm.abi_encode("balanceOf(address)", [address_flat])
    end

    test "should decode hexadecimal params" do
      address = :crypto.strong_rand_bytes(20)
      address_hex = Base.encode16(address)

      addresses = [:crypto.strong_rand_bytes(20), :crypto.strong_rand_bytes(20)]
      addresses_hex = Enum.map(addresses, &Base.encode16/1)

      assert Evm.abi_encode("(address, address[])", [address_hex, addresses_hex]) ==
               Evm.abi_encode("(address, address[])", [address, addresses])
    end
  end

  describe "abi_decode/2" do
    test "should decode abi with only types" do
      encoded_data =
        Base.encode16(
          <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 69, 116, 104, 101, 114, 32, 84, 111, 107, 101, 110,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
        )

      assert ["Ether Token"] == Evm.abi_decode("(string)", encoded_data)

      encoded_data =
        "0x" <>
          Base.encode16(
            <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 132, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 69, 116, 104, 101, 114, 32, 84,
              111, 107, 101, 110, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
          )

      assert [132, "Ether Token"] == Evm.abi_decode("(uint, string)", encoded_data)
      assert [132, "Ether Token"] == Evm.abi_decode("(int, string)", encoded_data)
    end

    test "should decode and return hexadecimal" do
      assert ["0x42ff8a93b309d0fde8acaea789c1f7f345a2c11f"] ==
               Evm.abi_decode(
                 "(address)",
                 "0x00000000000000000000000042ff8a93b309d0fde8acaea789c1f7f345a2c11f"
               )
    end
  end
end
