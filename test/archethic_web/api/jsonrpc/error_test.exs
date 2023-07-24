defmodule ArchethicWeb.API.JsonRPC.ErrorTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Error

  describe "get_error" do
    test "should return a structure according to JSON RPC specification" do
      assert Error.get_error(:parse_error) |> respect_json_rpc?()
      assert Error.get_error({:invalid_request, []}) |> respect_json_rpc?()
      assert Error.get_error({:invalid_method, ""}) |> respect_json_rpc?()
      assert Error.get_error({:invalid_method_params, []}) |> respect_json_rpc?()
      assert Error.get_error({:internal_error, ""}) |> respect_json_rpc?()

      assert Error.get_error({:custom_error, :transaction_exists, ""})
             |> respect_json_rpc?()
    end

    test "should return Json RPC standard error code" do
      assert %{"code" => -32700} = Error.get_error(:parse_error)
      assert %{"code" => -32600} = Error.get_error({:invalid_request, []})
      assert %{"code" => -32601} = Error.get_error({:invalid_method, ""})
      assert %{"code" => -32602} = Error.get_error({:invalid_method_params, []})
      assert %{"code" => -32603} = Error.get_error({:internal_error, ""})
    end

    test "should return custom error code for transaction context" do
      assert %{"code" => 122} = Error.get_error({:custom_error, :transaction_exists, ""})
    end
  end

  defp respect_json_rpc?(map) do
    Map.keys(map) |> Enum.all?(&(&1 in ["code", "message", "data"]))
  end
end
