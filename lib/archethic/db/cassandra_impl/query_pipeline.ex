defmodule ArchEthic.DB.CassandraImpl.QueryPipeline do
  @moduledoc false

  use Broadway

  alias ArchEthic.DB.CassandraImpl.QueryProducer

  alias Broadway.Message, as: BroadwayMessage

  def start_link(_args \\ []) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {QueryProducer, []},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 20, max_demand: 1]
      ]
    )
  end

  def transform(event, _) do
    %BroadwayMessage{
      data: event,
      acknowledger: {Broadway.NoopAcknowledger, _ack_ref = nil, _ack_data = nil}
    }
  end

  def prepare_messages(messages, _context) do
    Enum.map(messages, fn message ->
      BroadwayMessage.update_data(message, fn {query, mode, parameters, opts} ->
        {Xandra.prepare!(:xandra_conn, query), mode, parameters, opts}
      end)
    end)
  end

  def handle_message(_, message, _context) do
    BroadwayMessage.update_data(message, fn msg = {query, mode, parameters, opts} ->
      do_handle_message(query, mode, parameters, opts)
      msg
    end)
  end

  defp do_handle_message(query, :call, parameters, %{from: from}) do
    case Xandra.execute!(:xandra_conn, query, parameters) do
      page = %Xandra.Page{} ->
        results = Enum.to_list(page)
        GenStage.reply(from, results)

      _ ->
        GenStage.reply(from, :ok)
    end
  end

  defp do_handle_message(query, :streaming, parameters, %{from: from, ref: ref}) do
    from_pid = elem(from, 0)

    :xandra_conn
    |> Xandra.stream_pages!(query, parameters)
    |> Stream.flat_map(& &1)
    |> Enum.each(&send(from_pid, {:data, ref, &1}))

    send(from_pid, {:data_end, ref})
  end
end
