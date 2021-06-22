defmodule ArchEthic.DB.CassandraImpl.Consumer do
  @moduledoc false

  use GenStage

  alias ArchEthic.DB.CassandraImpl.Producer

  def start_link(args \\ []) do
    GenStage.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    {:consumer, :ok, subscribe_to: [{Producer, max_demand: 10}]}
  end

  def handle_events(events, _from, state) do
    events
    |> Task.async_stream(
      fn
        {batch = %Xandra.Batch{}, _, from} ->
          Xandra.execute!(:xandra_conn, batch)
          GenStage.reply(from, :ok)

        {query, parameters, from} ->
          prepare = Xandra.prepare!(:xandra_conn, query)

          case Xandra.execute!(:xandra_conn, prepare, parameters) do
            page = %Xandra.Page{} ->
              results = Enum.to_list(page)
              GenStage.reply(from, results)

            _ ->
              GenStage.reply(from, :ok)
          end
      end,
      ordered: false
    )
    |> Stream.run()

    {:noreply, [], state}
  end
end
