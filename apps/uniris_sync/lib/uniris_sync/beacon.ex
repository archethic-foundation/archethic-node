defmodule UnirisSync.Beacon do
  @moduledoc false

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  @doc """
  List of all transaction subsets
  """
  @spec all_subsets() :: list(binary())
  def all_subsets() do
    Enum.map(0..254, &(:binary.encode_unsigned(&1)))
  end

end
