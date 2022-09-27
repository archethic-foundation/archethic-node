defmodule ArchethicWeb.WebUtils do
  @moduledoc false
  @display_limit 10
  @doc """
   Nb of pages required to display all the transactions.

   ## Examples
      iex> total_pages(45)
      5
      iex> total_pages(40)
      4
      iex> total_pages(1)
      1
      iex> total_pages(10)
      1
      iex> total_pages(11)
      2
      iex> total_pages(0)
      0
  """
  @spec total_pages(tx_count :: non_neg_integer()) ::
          non_neg_integer()
  def total_pages(tx_count) when rem(tx_count, @display_limit) == 0,
    do: count_pages(tx_count)

  def total_pages(tx_count), do: count_pages(tx_count) + 1

  def count_pages(tx_count), do: div(tx_count, @display_limit)
end
