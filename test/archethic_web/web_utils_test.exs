defmodule ArchethicWeb.WebUtilsTest do
  alias ArchethicWeb.WebUtils

  use ExUnit.Case

  describe "from_bigint/2" do
    test "should format very big number correctly" do
      assert "184467440737.09551615" == WebUtils.from_bigint(2 ** 64 - 1)
    end
  end
end
