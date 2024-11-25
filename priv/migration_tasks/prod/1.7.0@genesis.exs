defmodule Migration_1_7_0 do
  @moduledoc false

  alias Archethic.DB
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.TransactionChain

  require Logger

  def run() do
    nodes = P2P.authorized_and_available_nodes()
    db_path = :persistent_term.get(:archethic_db_path)

    DB.list_io_transactions([])
    |> Stream.each(fn transaction ->
      if is_nil(transaction.validation_stamp.genesis_address) do
        # query for genesis
        storage_nodes = Election.storage_nodes(transaction.address, nodes)

        {:ok, genesis_address} =
          TransactionChain.fetch_genesis_address(transaction.address, storage_nodes)

        # update in memory
        transaction =
          put_in(
            transaction,
            [Access.key!(:validation_stamp), Access.key!(:genesis_address)],
            genesis_address
          )

        # update on disk
        File.rm!(ChainWriter.io_path(db_path, transaction.address))
        ChainWriter.write_io_transaction(transaction, db_path)
      end
    end)
    |> Stream.run()
  end
end
