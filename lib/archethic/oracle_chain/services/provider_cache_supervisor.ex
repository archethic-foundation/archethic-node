defmodule Archethic.OracleChain.Services.ProviderCacheSupervisor do
  @moduledoc """
  Supervise the several self-hydrating cache for the providers
  """

  use Supervisor

  alias Archethic.OracleChain.Services.HydratingCache

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(arg) do
    fetch_args = Keyword.fetch!(arg, :fetch_args)
    providers = Keyword.fetch!(arg, :providers)

    provider_child_specs =
      Enum.map(providers, fn {provider, opts} ->
        refresh_interval = Keyword.get(opts, :refresh_interval, 60_000)

        Supervisor.child_spec(
          {HydratingCache,
           [
             refresh_interval: refresh_interval,
             mfa: {provider, :fetch, [fetch_args]},
             name: cache_name(provider)
           ]},
          id: cache_name(provider)
        )
      end)

    children = provider_child_specs

    Supervisor.init(
      children,
      strategy: :one_for_one
    )
  end

  defp cache_name(module), do: :"#{module}Cache"

  @doc """
  Return the values from the several provider caches
  """
  @spec get_values(list(module())) :: list(any())
  def get_values(providers) do
    providers
    |> Enum.map(fn {provider, _} -> cache_name(provider) end)
    |> Enum.map(&HydratingCache.get/1)
    |> Enum.filter(&match?({:ok, {:ok, _}}, &1))
    |> Enum.map(fn
      {:ok, {:ok, val}} -> val
    end)
  end
end
