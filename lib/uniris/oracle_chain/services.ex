defmodule Uniris.OracleChain.Services do
  @moduledoc false

  require Logger

  alias Uniris.Crypto

  @doc """
  Fetch new data from the services by comparing with the previous content
  """
  @spec fetch_new_data(map()) :: map()
  def fetch_new_data(previous_content \\ %{}) do
    Enum.map(services(), fn {service, handler} ->
      Logger.debug("Fetch #{service} oracle data")
      {service, apply(handler, :fetch, [])}
    end)
    |> Enum.filter(fn
      {service, {:ok, data}} ->
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

      {service, _} ->
        Logger.error("Cannot request the Oracle provider #{service}")
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

  defp services do
    Application.get_env(:uniris, Uniris.OracleChain) |> Keyword.fetch!(:services)
  end
end
