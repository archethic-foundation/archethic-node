defmodule Archethic.Governance.Pools.MemTableLoader do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Governance.Pools
  alias Archethic.Governance.Pools.MemTable

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  # TODO: manage the enrollment of member in pools except for nodes and technical council

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    load_conf_member_pools()
    load_from_proposals()
    {:ok, []}
  end

  defp load_conf_member_pools do
    :archethic
    |> Application.get_env(Pools)
    |> Keyword.fetch!(:initial_members)
    |> Enum.each(fn {pool, members} ->
      Enum.each(members, fn
        {address, weight_factor} ->
          MemTable.put_pool_member(pool, Base.decode16!(address),
            weighted?: true,
            weighted?: true,
            weight_factor: weight_factor
          )

        address ->
          MemTable.put_pool_member(pool, Base.decode16!(address))
      end)
    end)
  end

  defp load_from_proposals do
    TransactionChain.list_transactions_by_type(:code_proposal, [:previous_public_key])
    |> Stream.each(fn %Transaction{previous_public_key: previous_public_key} ->
      first_public_key = TransactionChain.get_first_public_key(previous_public_key)

      MemTable.put_pool_member(:technical_council, first_public_key,
        weighted?: true,
        weight_factor: 1
      )
    end)
    |> Stream.run()
  end
end
