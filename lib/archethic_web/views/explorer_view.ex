defmodule ArchEthicWeb.ExplorerView do
  @moduledoc false

  use ArchEthicWeb, :view

  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.EndOfNodeSync
  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.Summary

  alias ArchEthic.SharedSecrets.NodeRenewal

  alias ArchEthic.P2P.Node

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
    {:ok, ip, port, transport, reward_address, key_certificate} =
      Node.decode_transaction_content(content)

    """
    IP: #{:inet.ntoa(ip)}
    Port: #{port}
    Transport: #{transport}
    Reward address: #{Base.encode16(reward_address)}
    Key certificate: #{Base.encode16(key_certificate)}
    """
  end

  def format_transaction_content(:beacon, content) do
    {%Slot{
       subset: subset,
       transaction_summaries: transaction_summaries,
       end_of_node_synchronizations: end_of_sync,
       p2p_view: %{availabilities: availabilities}
     }, _} = Slot.deserialize(content)

    transaction_summaries_stringified =
      Enum.map_join(transaction_summaries, "\n", fn %TransactionSummary{
                                                      address: address,
                                                      timestamp: timestamp,
                                                      type: type
                                                    } ->
        "#{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(address)} - #{type}"
      end)

    end_of_sync_stringified =
      Enum.map_join(end_of_sync, ",", fn %EndOfNodeSync{
                                           public_key: node_public_key,
                                           timestamp: timestamp
                                         } ->
        "#{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(node_public_key)}"
      end)

    """
    Subset: #{Base.encode16(subset)}

    Transactions:
    #{transaction_summaries_stringified}

    New node synchronizations:
    #{end_of_sync_stringified}

    P2P node availabilites: #{Utils.bitstring_to_integer_list(availabilities) |> Enum.join(",")}
    """
  end

  def format_transaction_content(:beacon_summary, content) do
    {%Summary{
       subset: subset,
       transaction_summaries: transaction_summaries,
       end_of_node_synchronizations: end_of_sync,
       node_availabilities: node_availabilities
     }, _} = Summary.deserialize(content)

    transaction_summaries_stringified =
      Enum.map_join(transaction_summaries, "\n", fn %TransactionSummary{
                                                      address: address,
                                                      timestamp: timestamp,
                                                      type: type
                                                    } ->
        "#{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(address)} - #{type}"
      end)

    end_of_sync_stringified =
      Enum.map_join(end_of_sync, ", ", fn %EndOfNodeSync{
                                            public_key: node_public_key,
                                            timestamp: timestamp
                                          } ->
        "#{DateTime.to_string(DateTime.truncate(timestamp, :second))} - #{Base.encode16(node_public_key)}"
      end)

    """
    Subset: #{Base.encode16(subset)}

    Transactions:
    #{transaction_summaries_stringified}

    New node synchronizations
    #{end_of_sync_stringified}

    P2P node availabilites: #{Utils.bitstring_to_integer_list(node_availabilities) |> Enum.join(",")}
    """
  end

  def format_transaction_content(:node_shared_secrets, content) do
    {:ok, daily_nonce_public_key, network_address} =
      NodeRenewal.decode_transaction_content(content)

    """
    daily nonce public key: #{Base.encode16(daily_nonce_public_key)}

    network address: #{Base.encode16(network_address)}
    """
  end

  def format_transaction_content(_, content), do: content
end
