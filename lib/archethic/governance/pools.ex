defmodule ArchEthic.Governance.Pools do
  @moduledoc """
  Governance pool management.

  The ArchEthic governance is spread across several pool of voters with different power or area of expertise.

  The pools are:
  - Foundation
  - Technical council
  - Ethical council
  - Uniris
  - Miners
  - Users

  For instance, every code proposal should be supervised and voted according to the technical council.
  Such as miners or users would not have the knowledge required to judge the effectiveness of the proposal.

  Hence, each pool will have dedicated threshold of acceptance regarding the votes for a given proposal.
  """

  alias ArchEthic.Crypto

  alias __MODULE__.MemTable

  alias ArchEthic.P2P

  @type pool ::
          :foundation | :technical_council | :ethical_council | :uniris | :miners | :users

  @pools [:foundation, :technical_council, :ethical_council, :uniris, :miners, :users]

  def names do
    @pools
  end

  @doc """
  Return the list of members for a given pool
  """
  @spec members_of(pool()) :: list(Crypto.key())
  def members_of(pool)
      when pool in [:foundation, :technical_council, :ethical_council, :archethic] do
    pool
    |> MemTable.list_pool_members()
    |> Enum.map(fn {key, _} -> key end)
  end

  def members_of(:miners), do: P2P.list_node_first_public_keys()

  def members_of(:users) do
    # TODO: find a way to get them
    []
  end

  @doc """
  Determines the pools for given public key
  """
  @spec member_of(Crypto.key()) :: list(pool())
  def member_of(public_key) when is_binary(public_key) do
    do_member_of(public_key, @pools)
  end

  defp do_member_of(public_key, pools, acc \\ [])

  defp do_member_of(public_key, [pool | rest], acc) do
    if public_key in members_of(pool) do
      do_member_of(public_key, rest, [pool | acc])
    else
      do_member_of(public_key, rest, acc)
    end
  end

  defp do_member_of(_public_key, [], acc) do
    [:users | acc]
  end

  @doc """
  Determine if the public key is member of a given pool
  """
  @spec member_of?(Crypto.key(), pool()) :: boolean()
  def member_of?(public_key, pool), do: public_key in members_of(pool)

  @doc """
  Return the threshold acceptance for a given pool

  Examples:
  - Technical council requires the most of the voters to be agree (90%) - because of the changes criticality
  - Others: requires a majority
  """
  @spec threshold_acceptance_for(pool()) :: float()
  def threshold_acceptance_for(:technical_council), do: 0.9
  def threshold_acceptance_for(pool) when pool in @pools, do: 0.51
end
