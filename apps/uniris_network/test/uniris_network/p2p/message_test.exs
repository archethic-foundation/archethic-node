defmodule UnirisNetwork.P2P.MessageTest do
  use ExUnit.Case
  use ExUnitProperties

  alias UnirisNetwork.P2P.Message

  test "encode/1 should return an encoded payload" do
    check all(payload <- StreamData.term()) do
      encoded_payload = Message.encode(payload)
      assert match?(<<_::binary-33, _::binary-64, _::binary>>, encoded_payload)
    end
  end

  test "decode/1 should return the decoded payload when is it valid" do
    check all(payload <- StreamData.term()) do
      encoded_payload = Message.encode(payload)
      assert match?({:ok, _, <<_::binary-33>>}, Message.decode(encoded_payload))

    end
  end

  test "decode/1 should return an error when the decoded data is malformed" do
    check all(encoded_payload <- StreamData.term()) do
      assert match?({:error, :invalid_payload}, Message.decode(encoded_payload))
    end
  end
end
