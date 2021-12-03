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
    Enum.map(messages, &do_prepare_message/1)
  end

  defp do_prepare_message(msg = %BroadwayMessage{data: {query, _, _, _}}) do
    case Xandra.prepare(:xandra_conn, query) do
      {:ok, prepared} ->
        BroadwayMessage.update_data(msg, fn {_, parameters, from, opts} ->
          {prepared, parameters, from, opts}
        end)

      {:error, reason} ->
        BroadwayMessage.failed(msg, "#{inspect(reason)}")
    end
  end

  def handle_message(_, message, _context) do
    BroadwayMessage.update_data(message, fn msg = {query, parameters, from, options} ->
      res = Xandra.execute!(:xandra_conn, query, parameters, options)
      GenStage.reply(from, res)

      msg
    end)
  end
end
