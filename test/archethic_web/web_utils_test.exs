defmodule ArchethicWeb.WebUtilsTest do
  alias ArchethicWeb.WebUtils

  use ExUnit.Case

  describe "from_bigint/2" do
    test "should format very big number correctly" do
      assert "184,467,440,737.09551615" == WebUtils.from_bigint(2 ** 64 - 1)
    end
  end

  describe "format_usd_amount/2" do
    test "should format very big number correctly" do
      assert "184,467,440,737.10$" == WebUtils.format_usd_amount(2 ** 64 - 1, 1.0)
      assert "18,446,744,073.71$" == WebUtils.format_usd_amount(2 ** 64 - 1, 0.1)
    end
  end

  describe "format_number_with_thousand_separator/1" do
    test "should return as is" do
      assert "1" == WebUtils.format_number_with_thousand_separator("1")
      assert "0" == WebUtils.format_number_with_thousand_separator("0")
      assert "0.0" == WebUtils.format_number_with_thousand_separator("0.0")
      assert "0.23" == WebUtils.format_number_with_thousand_separator("0.23")
      assert "0.20000003" == WebUtils.format_number_with_thousand_separator("0.20000003")
      assert "123" == WebUtils.format_number_with_thousand_separator("123")
      assert "123.0" == WebUtils.format_number_with_thousand_separator("123.0")
      assert "123.20000003" == WebUtils.format_number_with_thousand_separator("123.20000003")
    end

    test "should add separators" do
      assert "1,000" == WebUtils.format_number_with_thousand_separator("1000")
      assert "1,000,000" == WebUtils.format_number_with_thousand_separator("1000000")
      assert "100,010,000" == WebUtils.format_number_with_thousand_separator("100010000")
      assert "1,000,000,000" == WebUtils.format_number_with_thousand_separator("1000000000")
      assert "1,230.20000003" == WebUtils.format_number_with_thousand_separator("1230.20000003")

      assert "1,000,000,000,000.984" ==
               WebUtils.format_number_with_thousand_separator("1000000000000.984")
    end
  end
end
