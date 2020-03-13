defmodule UnirisValidation.DefaultImplTest do
  use ExUnit.Case

  alias UnirisChain.Transaction
  alias UnirisValidation.DefaultImpl, as: Validation

  import Mox

  setup :verify_on_exit!

  setup do
    DynamicSupervisor.which_children(UnirisValidation.MiningSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(UnirisValidation.MiningSupervisor, pid)
    end)
  end

  test "start_mining/1 should start a mining process under the dynamic supervisor" do
    tx = %Transaction{
      address: "",
      type: :transfer,
      timestamp: DateTime.utc_now(),
      data: %{},
      previous_public_key: "",
      previous_signature: "",
      origin_signature: ""
    }

    Validation.start_mining(tx, "welcome_node_public_key", [
      "validator_key1",
      "validator_key2"
    ])

    assert 1 == DynamicSupervisor.count_children(UnirisValidation.MiningSupervisor).active

    [{_, pid, :worker, [UnirisValidation.DefaultImpl.Mining]}] =
      DynamicSupervisor.which_children(UnirisValidation.MiningSupervisor)

    assert Process.alive?(pid)
  end
end
