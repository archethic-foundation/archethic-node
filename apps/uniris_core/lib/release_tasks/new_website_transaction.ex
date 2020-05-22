defmodule UnirisCore.ReleaseTasks.NewWebsiteTransaction do
  @doc """
  Example of content hosting transaction trigger by a node
  and published into the network
  """
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData

  def run(seed, index, content) do
    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          content: content
        },
        seed,
        index
      )

    UnirisCore.send_new_transaction(tx)
  end
end
