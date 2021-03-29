defmodule Uniris.Playbook do
  @moduledoc """
  Playbook is executed on a testnet to verify correctness of the testnet.
  """

  @doc """
  Run playbook.
  """
  @callback play!([String.t()], Keyword.t()) :: :ok
end
