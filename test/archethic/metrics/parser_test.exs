defmodule ArchEthic.Metrics.ParserTest do
  use ExUnit.Case

  test "structure of output of parse data" do
    assert Enum.count(ArchEthic.Metrics.Parser.run(get_dummy_data()), &validate_structure(&1)) ==
             length(ArchEthic.Metrics.Parser.run(get_dummy_data()))
  end

  def get_dummy_data() do
    """
    HELP archethic_self_repair_duration
    # TYPE archethic_self_repair_duration gauge
    archethic_self_repair_duration 3.610969045
    # HELP archethic_db_duration
    # TYPE archethic_db_duration histogram
    archethic_db_duration_sum{query="write_transaction_chain"} 5.5
    archethic_db_duration_count{query="write_transaction_chain"} 93
    archethic_db_duration_sum{query="get_transaction_chain"} 1161.8
    archethic_db_duration_count{query="get_transaction_chain"} 5284
    archethic_db_duration_sum{query="write_transaction"} 7.3
    archethic_db_duration_count{query="write_transaction"} 1211
    archethic_db_duration_bucket{query="get_transaction",le="+Inf"} 2061
    archethic_db_duration_sum{query="get_transaction"} 15.235701532000004
    archethic_db_duration_count{query="get_transaction"} 2061
    # HELP archethic_contract_parsing_duration
    # TYPE archethic_contract_parsing_duration histogram
    archethic_contract_parsing_duration_bucket{le="0.001"} 153
    archethic_contract_parsing_duration_bucket{le="+Inf"} 177
    archethic_contract_parsing_duration_sum 0.12
    archethic_contract_parsing_duration_count 177
    # HELP archethic_mining_full_transaction_validation_duration
    # TYPE archethic_mining_full_transaction_validation_duration histogram
    archethic_mining_full_transaction_validation_duration_bucket{le="0.01"} 0
    archethic_mining_full_transaction_validation_duration_bucket{le="+Inf"} 85
    archethic_mining_full_transaction_validation_duration_sum 31.9
    archethic_mining_full_transaction_validation_duration_count 85
    # HELP archethic_mining_fetch_context_duration
    # TYPE archethic_mining_fetch_context_duration histogram
    archethic_mining_fetch_context_duration_sum 8.2
    archethic_mining_fetch_context_duration_count 88
    # HELP archethic_mining_pending_transaction_validation_duration
    # TYPE archethic_mining_pending_transaction_validation_duration histogram
    archethic_mining_pending_transaction_validation_duration_bucket{le="0.001"} 20
    archethic_mining_pending_transaction_validation_duration_bucket{le="+Inf"} 87
    archethic_mining_pending_transaction_validation_duration_sum 11.4
    archethic_mining_pending_transaction_validation_duration_count 87
    # HELP archethic_election_storage_nodes_duration
    # TYPE archethic_election_storage_nodes_duration histogram
    archethic_election_storage_nodes_duration_bucket{nb_nodes="1",le="+Inf"} 1074
    archethic_election_storage_nodes_duration_sum{nb_nodes="1"} 0.032
    archethic_election_storage_nodes_duration_count{nb_nodes="1"} 1074
    archethic_election_storage_nodes_duration_bucket{nb_nodes="2",le="0.001"} 120
    archethic_election_storage_nodes_duration_sum{nb_nodes="2"} 0.011
    archethic_election_storage_nodes_duration_count{nb_nodes="2"} 122
    archethic_election_storage_nodes_duration_sum{nb_nodes="3"} 3.11
    archethic_election_storage_nodes_duration_count{nb_nodes="3"} 45719
    # HELP vm_memory_atom
    # TYPE vm_memory_atom gauge
    vm_memory_atom 1589609
    """
  end

  def validate_structure(metric) do
    case metric do
      %{metrics: [%{value: _}], name: _, type: "gauge"} ->
        true

      %{metrics: [%{:quantiles => _, "count" => _, "sum" => _}], name: _, type: "histogram"} ->
        true

      %{
        name: _,
        type: "histogram",
        metrics: [
          %{:labels => %{"nb_nodes" => _}, :quantiles => _, "count" => _, "sum" => _},
          %{:labels => %{"nb_nodes" => _}, :quantiles => _, "count" => _, "sum" => _} | _
        ]
      } ->
        true

      %{
        name: _,
        type: "histogram",
        metrics: [
          %{:labels => %{"query" => _}, :quantiles => _, "count" => _, "sum" => _},
          %{:labels => %{"query" => _}, :quantiles => _, "count" => _, "sum" => _} | _
        ]
      } ->
        true

      %{
        name: _,
        type: "histogram",
        metrics: [
          %{:labels => %{"message" => _}, :quantiles => _, "count" => _, "sum" => _},
          %{:labels => %{"message" => _}, :quantiles => _, "count" => _, "sum" => _} | _
        ]
      } ->
        true

      _ ->
        false
    end
  end
end
