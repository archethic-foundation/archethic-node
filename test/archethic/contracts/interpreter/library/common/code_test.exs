defmodule Archethic.Contracts.Interpreter.Library.Common.CodeTest do
  use ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Code

  # ----------------------------------------
  describe "is_same?/2" do
    test "should return true if codes are the same" do
      code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        Contract.set_content "Should work"
      end
      """

      assert Code.is_same?(code, code)
    end

    test "should return false if codes are different" do
      first_code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        Contract.set_content "Hello there"
      end
      """

      second_code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        Contract.set_content "When moon ?"
      end
      """

      refute Code.is_same?(first_code, second_code)
    end

    test "should return true even with difference in line return and line space" do
      first_code = ~S"""
      @version 1

      condition triggered_by: transaction, as: []

      actions triggered_by: transaction do
        Contract.set_content "Yolo"
      end
      """

      second_code = ~S"""


      @version 1

      condition triggered_by: transaction, as: []
      actions triggered_by: transaction do Contract.set_content "Yolo" end

      """

      assert Code.is_same?(first_code, second_code)
    end
  end

  # ----------------------------------------
  describe "is_valid?/1" do
    test "should return true if code is valid" do
      code = ~S"""
      @version 1

      condition triggered_by: transaction, as: [
        content: "No you're not"
      ]

      actions triggered_by: transaction do
        Contract.set_content "Woaw ! I'm a content !"
      end
      """

      assert Code.is_valid?(code)
    end

    test "should return false if code is invalid" do
      code = ~S"""
      @version 1

      condition which_is_not_valid: [
        content: "Poor code"
      ]

      actions triggered_by: transaction do
        Contract.set_content "You will never goes here"
      end
      """

      refute Code.is_valid?(code)
    end
  end
end
