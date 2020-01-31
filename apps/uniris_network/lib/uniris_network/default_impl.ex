defmodule UnirisNetwork.DefaultImpl do
  @moduledoc false

  alias UnirisNetwork.Node
  alias UnirisNetwork.SharedSecretStore

  @behaviour UnirisNetwork.Impl

  @impl true
  @spec storage_nonce() :: binary()
  def storage_nonce() do
    SharedSecretStore.storage_nonce()
  end

  @impl true
  @spec daily_nonce() :: binary()
  def daily_nonce() do
    SharedSecretStore.daily_nonce()
  end

  @impl true
  @spec origin_public_keys() :: list(binary())
  def origin_public_keys() do
    SharedSecretStore.origin_public_keys()
  end

  @impl true
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    DynamicSupervisor.which_children(UnirisNetwork.NodeSupervisor)
    |> Task.async_stream(fn {:undefined, pid, _, _} -> :sys.get_state(pid) end)
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  @impl true
  @spec node_info(binary()) :: {:ok, Node.t()} | {:error, :node_not_exists}
  def node_info(public_key) do
    case UnirisNetwork.NodeRegistry.lookup(public_key) do
      [{pid, _}] ->
        {:ok, Node.details(pid)}
      [] ->
        {:error, :node_not_exists}
    end
  end
  
end
