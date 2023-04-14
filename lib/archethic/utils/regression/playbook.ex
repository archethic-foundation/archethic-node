defmodule Archethic.Utils.Regression.Playbook do
  @moduledoc """
  Playbook is executed on a testnet/devnet to verify correctness of the network.
  """

  @doc """
  Given a list of nodes forming the network and options, play a scenario.
  """
  @callback play!([String.t()], Keyword.t()) :: :ok

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Archethic.Utils.Regression.Playbook
    end
  end
end
