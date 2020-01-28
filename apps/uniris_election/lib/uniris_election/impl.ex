defmodule UnirisElection.Impl do
  @moduledoc false

  @callback validation_nodes(
              transaction :: Transaction.pending(),
              network_nodes :: list(Node.t()),
              daily_nonce :: binary(),
              constraints :: [
                min_geo_patch: (() -> non_neg_integer()),
                validation_number: (Transaction.pending() -> non_neg_integer())
              ]
            ) :: list(Node.t())

  @callback storage_nodes(
              address :: binary(),
              network_nodes :: [Node.t()],
              storage_nonce :: binary(),
              constraints :: [
                min_geo_patch: (() -> non_neg_integer()),
                min_geo_patch_avg_availability: (() -> non_neg_integer()),
                number_replicas: (nonempty_list(Node.t()) -> non_neg_integer())
              ]
            ) :: [Node.t()]
end
