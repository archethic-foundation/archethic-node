defmodule UnirisCore.Storage.CassandraBackend.ChainQueryWorker do
  @moduledoc false

  alias UnirisCore.Storage.CassandraBackend

  use GenServer

  @query_statement """
  SELECT
    transaction_address as address,
    type,
    timestamp,
    data,
    previous_public_key,
    previous_signature,
    origin_signature,
    validation_stamp,
    cross_validation_stamps
  FROM uniris.transaction_chains
  WHERE chain_address=? and bucket=?
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def get(pid, address) do
    GenServer.call(pid, {:get, address})
  end

  def init(bucket: bucket) do
    {:ok, bucket}
  end

  def handle_call({:get, address}, from, bucket) do
    Task.start(fn ->
      prepared = Xandra.prepare!(:xandra_conn, @query_statement)

      res = Xandra.stream_pages!(:xandra_conn, prepared, _params = [Base.encode16(address), bucket])
      |> Stream.flat_map(& &1)
      |> Stream.map(&CassandraBackend.format_result_to_transaction/1)
      |> Enum.to_list()

      GenServer.reply(from, res)
    end)
    {:noreply, bucket}
  end
end
