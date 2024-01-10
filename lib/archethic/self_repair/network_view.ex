defmodule Archethic.SelfRepair.NetworkView do
  @moduledoc """
  The network view is 2 things:
  - the P2P view (list of all nodes)
  - the Network chains view (oracle/origin/nodesharedsecrets)

  It is useful to compare with other nodes to detect desynchronization.
  The P2P view is handled by the P2P module, we just do the hash here for convenience.
  """

  use GenServer
  @vsn 1

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.PubSub
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  require Logger

  # ------------------------------------------------------
  #               _
  #    __ _ _ __ (_)
  #   / _` | '_ \| |
  #  | (_| | |_) | |
  #   \__,_| .__/|_|
  #        |_|
  # ------------------------------------------------------

  @doc """
  Start the NetworkView server
  """
  @spec start_link(list()) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Return the hash of the P2P view
  """
  @spec get_p2p_hash() :: binary()
  def get_p2p_hash() do
    GenServer.call(__MODULE__, :get_p2p_hash)
  end

  @doc """
  Return the hash of the network chains view
  """
  @spec get_chains_hash() :: binary()
  def get_chains_hash() do
    GenServer.call(__MODULE__, :get_chains_hash)
  end

  @doc """
  Update the state with given transaction.
  GenServer is called only on relevant transactions.
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx = %Transaction{type: type})
      when type in [:node_shared_secrets, :oracle, :origin, :node] do
    GenServer.cast(__MODULE__, {:load_transaction, tx})
  end

  def load_transaction(_), do: :ok

  # ------------------------------------------------------
  #            _ _ _                _
  #   ___ __ _| | | |__   __ _  ___| | _____
  #  / __/ _` | | | '_ \ / _` |/ __| |/ / __|
  # | (_| (_| | | | |_) | (_| | (__|   <\__ \
  #  \___\__,_|_|_|_.__/ \__,_|\___|_|\_|___/
  #
  # ------------------------------------------------------

  def init([]) do
    state =
      if Archethic.up?() do
        fetch_initial_state()
      else
        Logger.info("NetworkView: Waiting for Node to complete Bootstrap. ")
        PubSub.register_to_node_status()
        :not_initialized
      end

    {:ok, state, {:continue, :update_chains_hash}}
  end

  # ------------------------------------------------------
  def handle_call(:get_chains_hash, _from, state = %{chains_hash: chains_hash}) do
    {:reply, chains_hash, state}
  end

  def handle_call(:get_p2p_hash, _from, state = %{p2p_hash: p2p_hash}) do
    {:reply, p2p_hash, state}
  end

  def handle_call(_msg, _from, state = :not_initialized) do
    {:reply, :error, state}
  end

  # ------------------------------------------------------
  def handle_cast({:load_transaction, %Transaction{type: :node}}, state = %{}) do
    new_state = Map.put(state, :p2p_hash, do_get_p2p_hash())

    {:noreply, new_state}
  end

  def handle_cast(
        {:load_transaction,
         %Transaction{type: type, address: address, previous_public_key: previous_public_key}},
        state = %{origin: origin}
      ) do
    new_state =
      case type do
        :origin ->
          # update the correct origin family
          origin_family = SharedSecrets.origin_family_from_public_key(previous_public_key)
          Map.put(state, type, Map.put(origin, origin_family, address))

        _ ->
          Map.put(state, type, address)
      end

    {:noreply, new_state, {:continue, :update_chains_hash}}
  end

  def handle_cast(_msg, state = :not_initialized) do
    {:noreply, state}
  end

  # ------------------------------------------------------
  def handle_info(:node_up, _state) do
    state = fetch_initial_state()
    {:noreply, state, {:continue, :update_chains_hash}}
  end

  def handle_info(:node_down, state) do
    {:noreply, state}
  end

  # ------------------------------------------------------
  def handle_continue(:update_chains_hash, state = :not_initialized) do
    {:noreply, state}
  end

  def handle_continue(
        :update_chains_hash,
        state = %{
          node_shared_secrets: node_shared_secrets,
          oracle: oracle,
          origin: origin
        }
      ) do
    chains_hash =
      :crypto.hash(:sha256, [
        node_shared_secrets,
        oracle,
        Map.values(origin) |> Enum.sort()
      ])

    {:noreply, %{state | chains_hash: chains_hash}}
  end

  # ------------------------------------------------------
  #              _            _
  #   _ __  _ __(___   ____ _| |_ ___
  #  | '_ \| '__| \ \ / / _` | __/ _ \
  #  | |_) | |  | |\ V | (_| | ||  __/
  #  | .__/|_|  |_| \_/ \__,_|\__\___|
  #  |_|
  #
  # ------------------------------------------------------
  defp do_get_p2p_hash() do
    P2P.list_nodes()
    |> Enum.map(& &1.last_public_key)
    |> Enum.sort()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp fetch_initial_state() do
    last_known_nss_address =
      SharedSecrets.genesis_address(:node_shared_secrets)
      |> get_last_address()

    # There are 1 genesis address per origin (for now 3 origins)
    last_known_origin_addresses =
      SharedSecrets.list_origin_families()
      |> Enum.map(fn origin_family ->
        genesis_address =
          SharedSecrets.get_origin_family_seed(origin_family)
          |> Crypto.derive_keypair(0)
          |> elem(0)
          |> Crypto.derive_address()

        {origin_family, genesis_address}
      end)
      |> Enum.map(fn {origin_family, genesis_address} ->
        {origin_family, get_last_address(genesis_address)}
      end)
      |> Enum.into(%{})

    last_known_oracle_address = OracleChain.genesis_address() |> get_last_address()

    %{
      chains_hash: <<>>,
      p2p_hash: do_get_p2p_hash(),
      node_shared_secrets: last_known_nss_address,
      origin: last_known_origin_addresses,
      oracle: last_known_oracle_address
    }
  end

  defp get_last_address(nil), do: ""

  defp get_last_address(genesis_address) do
    {local_last_address, _} = TransactionChain.get_last_address(genesis_address)
    local_last_address
  end
end
