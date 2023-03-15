defmodule Archethic.ContractFactory do
  @moduledoc false

  def valid_version1_contract(opts \\ []) do
    code = ~S"""
    condition inherit: [
      content: true
    ]

    condition transaction: [
      uco_transfers: Map.size() > 0
    ]

    actions triggered_by: transaction do
      Contract.set_content "hello"
    end
    """

    if Keyword.get(opts, :version_attribute, true) do
      """
      @version 1
      #{code}
      """
    else
      code
    end
  end

  def valid_legacy_contract() do
    ~S"""
    condition inherit: [
      content: true
    ]

    condition transaction: [
      uco_transfers: size() > 0
    ]

    actions triggered_by: transaction do
      set_content "hello"
    end
    """
  end
end
