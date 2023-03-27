defmodule Archethic.OracleChain.Services do
  @moduledoc false

  require Logger

  alias Archethic.Crypto

  @doc """
  Fetch new data from the services by comparing with the previous content
  """
  @spec fetch_new_data(map()) :: map()
  def fetch_new_data(previous_content \\ %{}) do
    Enum.map(services(), fn {service, handler} ->
      Logger.debug("Fetching #{service} oracle data...")
      {service, handler.fetch()}
    end)
    |> Enum.filter(fn
      {service, {:ok, data}} ->
        Logger.debug("Oracle data for #{service}: #{inspect(data)}")

        previous_digest =
          previous_content
          |> Map.get(Atom.to_string(service))
          |> Jason.encode!()
          |> Crypto.hash()

        new_digest =
          data
          |> Jason.encode!()
          |> Crypto.hash()

        new_digest != previous_digest

      {service, reason} ->
        Logger.warning(
          "Cannot request the Oracle provider #{service} - reason: #{inspect(reason)}"
        )

        false
    end)
    |> Enum.into(%{}, fn {service, {:ok, data}} -> {service, data} end)
  end

  @doc """
  Verify the data generated from an oracle transaction
  """
  @spec verify_correctness?(map()) :: boolean()
  def verify_correctness?(data = %{}) do
    Enum.all?(data, fn
      {name, data} ->
        handler = Keyword.get(services(), String.to_existing_atom(name))
        apply(handler, :verify?, [data])
    end)
  end

  @doc """
  Parse and ensure the service data are valid according to the service provider's rules
  """
  @spec parse_data(map()) :: {:ok, map()} | :error
  def parse_data(data) when is_map(data) do
    services =
      services()
      |> Enum.map(&{Atom.to_string(elem(&1, 0)), elem(&1, 1)})
      |> Enum.into(%{})

    valid? =
      Enum.all?(data, fn {service, service_data} ->
        with true <- Map.has_key?(services, service),
             {:ok, _} <- apply(Map.get(services, service), :parse_data, [service_data]) do
          true
        else
          _ ->
            false
        end
      end)

    if valid?, do: {:ok, data}, else: :error
  end

  def parse_data(_), do: :error

  defp services do
    Application.get_env(:archethic, Archethic.OracleChain) |> Keyword.fetch!(:services)
  end

  @doc """
  List all the service cache supervisor specs
  """
  @spec cache_service_supervisor_specs() :: list(Supervisor.child_spec())
  def cache_service_supervisor_specs do
    Enum.map(services(), fn {_service_name, handler} ->
      handler.cache_child_spec()
    end)
  end
end
