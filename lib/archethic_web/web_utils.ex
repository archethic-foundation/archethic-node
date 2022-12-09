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

  def keep_remote_ip(conn) do
    %{"remote_ip" => conn.remote_ip}
  end

  # TO DO:
  # Dictate this policy what seems best in production w.r.t mainnet proxy and url
  def content_security_policy do
    case(Mix.env()) do
      :prod ->
        ""

      _ ->
        ""
        # "default-src 'self' 'unsafe-eval' 'unsafe-inline' ;" <>
        #   "font-src https://fonts.googleapis.com;" <>
        #   "https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtr6Hw2aXpsog.woff2;'" <>
        #   "style-src-ele https://fonts.googleapis.com/css2?family=Montserrat&display=swap;"
    end
  end
end
