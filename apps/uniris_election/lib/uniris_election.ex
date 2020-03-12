defmodule UnirisElection do
  @moduledoc """
  Uniris provides a random and rotating node election based on heuristic algorithms
  and constraints to ensure a fair distributed processing and data storage among its network.

  """

  alias UnirisChain.Transaction

  @behaviour __MODULE__.Impl

  @doc """
  Get the elected validation nodes for a given transaction and a list of nodes.

  Each nodes public key is rotated with the daily nonce
  to provide an unpredictable order yet reproducible.

  To achieve an unpredictable, global but locally executed, verifiable and reproducible
  election, each election is based on:
  - an unpredictable element: hash of transaction
  - an element known only by authorized nodes: daily nonce
  - an element difficult to predict: last public key of the node
  - the computation of the rotating keys

  Then each nodes selection is reduce via heuristic constraints
  - a minimum of distinct geographical zones to distributed globally the validations
  - require number of validation for the given transaction criticity
  (ie: sum of UCO to transfer - a high UCO transfer will require a high number of validations)

  """
  @impl true
  @spec validation_nodes(UnirisChain.Transaction.pending()) :: [Node.t()]
  def validation_nodes(tx = %Transaction{}) do
    impl().validation_nodes(tx)
  end

  @doc """
  Get the elected storage nodes for a given transaction address and a list of nodes.

  Each nodes first public key is rotated with the storage nonce and the transaction address
  to provide an reproducible list of nodes ordered.

  To perform the election, the rotating algorithm is based on:
  - the transaction address
  - an stable known element: storage nonce
  - the first public key of each node
  - the computation of the rotating keys

  From this sorted nodes, a selection is made by reducing it via heuristic constraints:
  - a require number of storage replicas from the given availability of the nodes
  - a minimum of distinct geographical zones to distributed globally the validations
  - a minimum avergage availability by geographical zones
  """
  @impl true
  @spec storage_nodes(address :: binary()) :: [Node.t()]
  def storage_nodes(address) when is_binary(address) do
    impl().storage_nodes(address)
  end

  defp impl(), do: Application.get_env(:uniris_election, :impl, __MODULE__.DefaultImpl)
end
