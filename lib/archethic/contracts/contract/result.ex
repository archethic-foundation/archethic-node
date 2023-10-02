defmodule Archethic.Contracts.Contract.Result do
  @moduledoc false

  alias __MODULE__.Error
  alias __MODULE__.Success
  alias __MODULE__.Noop

  @typedoc """
  This type represent the result of a Smart Contract's execution
  """
  @type t() :: Error.t() | Success.t() | Noop.t()

  @doc """
  Is the result considered as valid?
  """
  @spec valid?(t()) :: boolean()
  def valid?(%Error{}), do: false
  def valid?(%Success{}), do: true
  def valid?(%Noop{}), do: true
end
