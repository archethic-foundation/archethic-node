defmodule Uniris.ContractsTest do
  use ExUnit.Case

  alias Uniris.Contracts
  alias Uniris.Contracts.Contract
  alias Uniris.Contracts.Contract.Conditions
  alias Uniris.Contracts.Contract.Triggers

  @moduletag capture_log: true

  doctest Contracts
end
