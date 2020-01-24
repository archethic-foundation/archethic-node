defmodule UnirisNetwork.P2P.PayloadTest do
  use ExUnit.Case
  use ExUnitProperties

  test "encode/1 should return an encoded payload" do
    check all(payload <- StreamData.term()) do
      encoded_payload = UnirisNetwork.P2P.Payload.encode(payload)
      assert match?(<<_::binary-33, _::binary-64, _::binary>>, encoded_payload)
    end
  end

  test "decode/1 should return the decoded payload when is it valid" do
    check all(payload <- StreamData.term()) do
      encoded_payload = UnirisNetwork.P2P.Payload.encode(payload)
      assert match?({:ok, _, <<_::binary-33>>}, UnirisNetwork.P2P.Payload.decode(encoded_payload))

    end
  end

  test "decode/1 should return an error when the decoded data is malformed" do
    check all(encoded_payload <- StreamData.term()) do
      assert match?({:error, :invalid_payload}, UnirisNetwork.P2P.Payload.decode(encoded_payload))
    end
  end
end
