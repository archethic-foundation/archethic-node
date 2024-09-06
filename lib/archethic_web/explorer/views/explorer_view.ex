defmodule ArchethicWeb.Explorer.ExplorerView do
  @moduledoc false

  use ArchethicWeb.Explorer, :view
  use ArchethicWeb.Explorer, :live_component

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.Summary

  alias Archethic.SharedSecrets
  alias Archethic.SharedSecrets.NodeRenewal

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.Utils

  alias Archethic.Crypto

  alias Phoenix.Naming

  def roles_to_string(roles) do
    roles
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map_join(", ", &String.replace(&1, "_", " "))
  end

  def format_transaction_type(type, opts \\ []) do
    formatted_type =
      type
      |> Naming.humanize()
      |> String.upcase()

    if Keyword.get(opts, :tag, true) do
      content_tag("span", formatted_type, class: "tag is-gradient")
    else
      content_tag("span", formatted_type)
    end
  end

  def is_json_content?(content) do
    case Jason.decode(content) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def format_transaction_content(:node, content) do
    {:ok, ip, port, http_port, transport, reward_address, origin_public_key, key_certificate} =
      Node.decode_transaction_content(content)

    """
    IP: #{:inet.ntoa(ip)}
    P2P Port: #{port}
    HTTP Port: #{http_port}
    Transport: #{transport}
    Reward address: #{Base.encode16(reward_address)}
    Origin public key: #{Base.encode16(origin_public_key)}
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
        node_list = Archethic.BeaconChain.Subset.P2PSampling.list_nodes_to_sample(subset)

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
        node_list = Archethic.BeaconChain.Subset.P2PSampling.list_nodes_to_sample(subset)

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
    {:ok, daily_nonce_public_key} = NodeRenewal.decode_transaction_content(content)

    """
    daily nonce public key: #{Base.encode16(daily_nonce_public_key)}
    """
  end

  def format_transaction_content(:origin, content) do
    content
    |> get_origin_public_key_and_certificate()
    |> format_origin_content()
  end

  def format_transaction_content(_, content) do
    case Jason.decode(content) do
      {:ok, _} -> Jason.Formatter.pretty_print_to_iodata(content)
      _ -> content
    end
  end

  @spec format_origin_content(tuple()) :: String.t()
  defp format_origin_content({family, key, key_certificate}) do
    ~s"""
    #{family} origin public key : #{Base.encode16(key)}
    origin public key certificate: #{Base.encode16(key_certificate)}
    """
  end

  @spec get_origin_public_key_and_certificate(binary()) :: {atom(), binary(), binary()}
  defp get_origin_public_key_and_certificate(<<curve_id::8, origin_id::8, rest::binary>>) do
    key_size = Crypto.key_size(curve_id)
    <<key::binary-size(key_size), rest::binary>> = rest

    <<key_certificate_size::16, key_certificate::binary-size(key_certificate_size), _::binary>> =
      rest

    family = SharedSecrets.get_origin_family_from_origin_id(origin_id)

    {family, key, key_certificate}
  end

  def burning_address, do: LedgerOperations.burning_address()

  def format_wasm_spec(%Archethic.Contracts.WasmSpec{
        version: version,
        upgrade_opts: upgrade_opts,
        public_functions: public_functions,
        triggers: triggers
      }) do
    upgrade_spec =
      if upgrade_opts != nil do
        """
        - enabled: true
        - allow_update_from: #{Base.encode16(upgrade_opts.from)}
        """
      else
        """
        - enabled: false
        """
      end

    """
    type: "WebAssembly contract"
    version: #{version}
    upgrade:
    #{upgrade_spec}
    triggers:
    #{Enum.map_join(triggers, "\n", fn %Archethic.Contracts.WasmTrigger{function_name: function, type: trigger} ->
      stringified_trigger = case trigger do
        {type, arg} -> "#{type} at #{arg}"
        trigger -> trigger
      end
      " - action: #{function}\n   trigger: #{stringified_trigger}"
    end)}
    public_functions:
    #{Enum.map_join(public_functions, "\n", fn function -> " - #{function}" end)}
    """
  end
end
