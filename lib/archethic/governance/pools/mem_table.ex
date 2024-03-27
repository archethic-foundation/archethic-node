defmodule Archethic.Governance.Pools.MemTable do
  @moduledoc false

  use Agent
  alias Archethic.Governance.Pools

  @doc """
  Initialize a memory table for the governance pool member distribution

  ## Examples

      iex> {:ok, pid} = MemTable.start_link()
      ...> :sys.get_state(pid)
      %{technical_council: %{}, ethical_council: %{}, uniris: %{}, foundation: %{}}
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(_args \\ []) do
    Agent.start_link(
      fn ->
        %{technical_council: %{}, ethical_council: %{}, uniris: %{}, foundation: %{}}
      end,
      name: __MODULE__
    )
  end

  @doc """
  Put a member to a list of pools

  ## Examples

      iex> {:ok, pid} = MemTable.start_link()
      ...> 
      ...> MemTable.put_pool_member(:technical_council, "@Alice2", weighted?: true, weight_factor: 1)
      ...> 
      ...> MemTable.put_pool_member(:technical_council, "@Alice2", weighted?: true, weight_factor: 1)
      ...> 
      ...> :sys.get_state(pid)
      %{technical_council: %{"@Alice2" => 2}, ethical_council: %{}, uniris: %{}, foundation: %{}}
  """
  @spec put_pool_member(pool_name :: Pools.pool(), address :: binary(), options :: Keyword.t()) ::
          :ok
  def put_pool_member(pool, member_address, opts \\ [])
      when is_binary(member_address) and is_list(opts) do
    weighted? = Keyword.get(opts, :weighted?, false)
    weight_factor = Keyword.get(opts, :weight_factor, 0)

    if weighted? do
      put_and_update_weight(pool, member_address, weight_factor)
    else
      put(pool, member_address)
    end
  end

  defp put_and_update_weight(pool, member, weight_factor) do
    Agent.update(__MODULE__, fn distribution ->
      case get_in(distribution, [pool, member]) do
        nil ->
          put_in(distribution, [pool, member], weight_factor)

        _ ->
          update_in(distribution, [pool, member], &(&1 + weight_factor))
      end
    end)
  end

  defp put(pool, member) do
    Agent.update(__MODULE__, fn distribution -> put_in(distribution, [pool, member], 0) end)
  end

  @doc """
  Return the list of members for a given pool

  ## Examples

      iex> {:ok, _pid} = MemTable.start_link()
      ...> 
      ...> MemTable.put_pool_member(:technical_council, "@Alice2", weighted?: true, weight_factor: 1)
      ...> 
      ...> MemTable.put_pool_member(:technical_council, "@Bob5", weighted?: true, weight_factor: 1)
      ...> 
      ...> MemTable.put_pool_member(:technical_council, "@Alice2", weighted?: true, weight_factor: 1)
      ...> 
      ...> MemTable.list_pool_members(:technical_council)
      [{"@Alice2", 2}, {"@Bob5", 1}]
  """
  @spec list_pool_members(Pools.pool()) :: list({binary(), weight :: non_neg_integer()})
  def list_pool_members(pool) do
    Agent.get(__MODULE__, fn distribution ->
      distribution
      |> Map.get(pool)
      |> Enum.to_list()
    end)
  end
end
