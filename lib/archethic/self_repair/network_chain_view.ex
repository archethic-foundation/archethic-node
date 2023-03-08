defmodule Archethic.SelfRepair.NetworkChainView do
  @moduledoc """
  The network chain view is a local view on the network chains.
  It is useful to compare with other nodes to detect desynchronization.
  """

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.OracleChain
  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.PubSub
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  require Logger

  defmodule State do
    defstruct [
      # binary()
      node_shared_secrets: nil,
      # binary()
      oracle: nil,
      # list(binary())
      origin: []
    ]
  end

  #               _
  #    __ _ _ __ (_)
  #   / _` | '_ \| |
  #  | (_| | |_) | |
  #   \__,_| .__/|_|
  #        |_|

  @doc """
  Start the NetworkChainView server
  """
  @spec start_link(list()) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Return the hash of the node chain view
  """
  @spec get_node_chain_hash() :: binary()
  def get_node_chain_hash() do
    # this is not using the genserver
    # since the nodes' state is already in the P2P module
    P2P.authorized_and_available_nodes()
    |> Enum.map_join(& &1.last_public_key)
    |> Crypto.hash()
  end

  @doc """
  Return the hash of the scheduled chains (& origin)
  """
  @spec get_scheduled_chains_hash() :: binary()
  def get_scheduled_chains_hash() do
    GenServer.call(__MODULE__, :get_scheduled_chains_hash)
  end

  @doc """
  Update the state with given transaction.
  GenServer is called only on relevant transactions.
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        type: type,
        address: address
      })
      when type in [:node_shared_secrets, :oracle, :origin] do
    GenServer.cast(__MODULE__, {:load_transaction, type, address})
  end

  def load_transaction(_), do: :ok

  #            _ _ _                _
  #   ___ __ _| | | |__   __ _  ___| | _____
  #  / __/ _` | | | '_ \ / _` |/ __| |/ / __|
  # | (_| (_| | | | |_) | (_| | (__|   <\__ \
  #  \___\__,_|_|_|_.__/ \__,_|\___|_|\_|___/
  #

  def init([]) do
    state =
      if Archethic.up?() do
        fetch_initial_state()
      else
        Logger.info("NetworkChainView: Waiting for Node to complete Bootstrap. ")
        PubSub.register_to_node_status()
        :not_initialized
      end

    {:ok, state}
  end

  def handle_call(:get_scheduled_chains_hash, _from, state = %State{}) do
    hash =
      [
        state.node_shared_secrets,
        state.oracle,
        state.origin |> Enum.join()
      ]
      |> Enum.join()
      |> Crypto.hash()

    {:reply, hash, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :error, state}
  end

  def handle_cast({:load_transaction, transaction_type, address}, state = %State{}) do
    new_state =
      case transaction_type do
        :origin ->
          Map.update(state, transaction_type, [address], &[address | &1])

        _ ->
          Map.put(state, transaction_type, address)
      end

    {:noreply, new_state}
  end

  def handle_info(:node_up, _state) do
    state = fetch_initial_state()
    {:noreply, state}
  end

  def handle_info(:node_down, state) do
    {:noreply, state}
  end

  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  #

  defp fetch_initial_state() do
    {last_known_nss_address, _} =
      SharedSecrets.genesis_address(:node_shared_secrets)
      |> TransactionChain.get_last_address()

    # There are 1 genesis address per origin (for now 3 origins)
    last_known_origin_addresses =
      SharedSecrets.genesis_address(:origin)
      |> Enum.map(fn genesis_address ->
        {last_known_origin_address, _} = TransactionChain.get_last_address(genesis_address)
        last_known_origin_address
      end)

    {last_known_oracle_address, _} =
      OracleChain.get_current_genesis_address()
      |> TransactionChain.get_last_address()

    %State{
      node_shared_secrets: last_known_nss_address,
      origin: last_known_origin_addresses,
      oracle: last_known_oracle_address
    }
  end
end
