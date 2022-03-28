defmodule ArchEthic.DB.EmbeddedImpl do
  alias __MODULE__.Index
  alias __MODULE__.Reader
  alias __MODULE__.Writer

  alias ArchEthic.TransactionChain.Transaction

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

 # @behaviour ArchEthic.DB

  @spec write_transaction_chain(list(Transaction.t())) :: :ok
  def write_transaction_chain(chain) do
    sorted_chain = Enum.sort_by(chain, & &1.validation_stamp.timestamp, {:asc, DateTime})

    first_tx = List.first(sorted_chain)
    genesis_address = Transaction.previous_address(first_tx)

    Enum.each(sorted_chain, fn tx ->
      Writer.append_transaction(genesis_address, tx)
    end)
  end

  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx) do
    previous_address = Transaction.previous_address(tx)

    case Index.get_tx_entry(previous_address) do
      {:ok, %{genesis_address: genesis_address}} ->
        Writer.append_transaction(genesis_address, tx)

      {:error, :not_exists} ->
        Writer.append_transaction(previous_address, tx)
    end
  end

  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) do
    Index.transaction_exists?(address)
  end

  defdelegate get_transaction(address, fields \\ []), to: Reader
  defdelegate get_transaction_chain(address, fields \\ [], paging_state \\ nil), to: Reader
end
