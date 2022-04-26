defmodule ArchEthicWeb.ExplorerView do
  @moduledoc false

  use ArchEthicWeb, :view

  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Summary

  alias ArchEthic.SharedSecrets.NodeRenewal

  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.TransactionSummary

  alias ArchEthic.Utils

  alias Phoenix.Naming

  def roles_to_string(roles) do
    roles
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map_join(", ", &String.replace(&1, "_", " "))
  end

  def format_transaction_type(type) do
    formatted_type =
      type
      |> Naming.humanize()
      |> String.upcase()

    content_tag("span", formatted_type, class: "tag is-warning is-light")
  end

  def format_transaction_content(:node, content) do
    {:ok, ip, port, http_port, transport, reward_address, key_certificate} =
      Node.decode_transaction_content(content)

    """
    IP: #{:inet.ntoa(ip)}
    Port: #{port}
    HTPPort: #{http_port}
    Transport: #{transport}
    Reward address: #{Base.encode16(reward_address)}
    Key certificate: #{Base.encode16(key_certificate)}
    """
  end

  def format_transaction_content(:beacon, content) do
    {%Slot{
       subset: subset,
       transaction_attestations: transaction_attestations,
       end_of_node_synchronizations: end_of_sync,
       p2p_view: %{availabilities: availabilities}
     }, _} = Slot.deserialize(content)

    content = ["Subset: #{Base.encode16(subset)}"]

    content =
      if Enum.empty?(transaction_attestations) do
        content
      else
        transaction_stringified =
          Enum.map_join(transaction_attestations, "\n", fn %ReplicationAttestation{
                                                             transaction_summary:
                                                               %TransactionSummary{
                                                                 address: address,
                                                                 timestamp: timestamp,
                                                                 type: type
                                                               },
                                                             confirmations: confirmations
                                                           } ->
            "#{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(address)} - #{type} - (#{length(confirmations)} confirmations)"
          end)

        content ++ ["\n", "Transactions:\n", transaction_stringified]
      end

    content =
      if Enum.empty?(end_of_sync) do
        content
      else
        end_of_sync_stringified =
          Enum.map_join(end_of_sync, ",", fn %EndOfNodeSync{
                                               public_key: node_public_key,
                                               timestamp: timestamp
                                             } ->
            "- #{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(node_public_key)}"
          end)

        content ++ ["\n", "New node synchronizations: \n", end_of_sync_stringified]
      end

    p2p_availabilities = Utils.bitstring_to_integer_list(availabilities)

    content =
      if Enum.empty?(p2p_availabilities) do
        content
      else
        node_list = ArchEthic.BeaconChain.Subset.P2PSampling.list_nodes_to_sample(subset)

        p2p_content =
          p2p_availabilities
          |> Enum.with_index()
          |> Enum.map_join("\n", fn
            {1, index} ->
              %Node{first_public_key: first_public_key} = Enum.at(node_list, index)
              "- #{Base.encode16(first_public_key)}: available"

            {0, index} ->
              %Node{first_public_key: first_public_key} = Enum.at(node_list, index)
              "- #{Base.encode16(first_public_key)}: unavailable"
          end)

        content ++
          [
            "\n",
            "P2P node availabilities: \n",
            p2p_content
          ]
      end

    content
  end

  def format_transaction_content(:beacon_summary, content) do
    {%Summary{
       subset: subset,
       transaction_attestations: transaction_attestations,
       node_availabilities: node_availabilities
     }, _} = Summary.deserialize(content)

    content = ["Subset: #{Base.encode16(subset)}\n"]

    content =
      if Enum.empty?(transaction_attestations) do
        content
      else
        transaction_stringified =
          Enum.map_join(transaction_attestations, "\n", fn %ReplicationAttestation{
                                                             transaction_summary:
                                                               %TransactionSummary{
                                                                 address: address,
                                                                 timestamp: timestamp,
                                                                 type: type
                                                               },
                                                             confirmations: confirmations
                                                           } ->
            "- #{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(address)} - #{type} - (#{length(confirmations)} confirmations)"
          end)

        content ++ ["\n", "Transactions:\n", transaction_stringified]
      end

    p2p_availabilities = Utils.bitstring_to_integer_list(node_availabilities)

    content =
      if Enum.empty?(p2p_availabilities) do
        content
      else
        node_list = ArchEthic.BeaconChain.Subset.P2PSampling.list_nodes_to_sample(subset)

        p2p_content =
          p2p_availabilities
          |> Enum.with_index()
          |> Enum.map_join("\n", fn
            {1, index} ->
              %Node{first_public_key: first_public_key} = Enum.at(node_list, index)
              "- #{Base.encode16(first_public_key)}: available"

            {0, index} ->
              %Node{first_public_key: first_public_key} = Enum.at(node_list, index)
              "- #{Base.encode16(first_public_key)}: unavailable"
          end)

        content ++
          [
            "\n",
            "P2P node availabilities: \n",
            p2p_content
          ]
      end

    content
  end

  def format_transaction_content(:node_shared_secrets, content) do
    {:ok, daily_nonce_public_key, network_address} =
      NodeRenewal.decode_transaction_content(content)

    """
    daily nonce public key: #{Base.encode16(daily_nonce_public_key)}

    network address: #{Base.encode16(network_address)}
    """
  end

  def format_transaction_content(:origin_shared_secrets, content) do
    Base.encode16(content)
  end

  def format_transaction_content(_, content), do: content
end
