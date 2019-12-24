defmodule UnirisElection do
  @moduledoc """
  Uniris provides a random and rotating node election based on heuristic algorithms
  and constraints to ensure a fair distributed processing and data storage among its network.

  """

  alias UnirisChain.Transaction
  alias UnirisCrypto, as: Crypto
  alias UnirisElection.HeuristicConstraints, as: Constraints

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

  ## Examples

      iex> tx = %UnirisChain.Transaction{
      ...>  address: "0489F19A241A5BA435CBD533EFA4D446696873030DA0B55BC64C6EF0184AA2F6",
      ...>  timestamp: 1573054121,
      ...>  type: :ledger,
      ...>  data: %UnirisChain.Transaction.Data{
      ...>    ledger: %UnirisChain.Transaction.Data.Ledger{
      ...>      uco: %UnirisChain.Transaction.Data.Ledger.UCO{
      ...>         transfers: [
      ...>             %UnirisChain.Transaction.Data.Ledger.Transfer{
      ...>               to: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824",
      ...>               amount: 2
      ...>             }
      ...>         ]
      ...>      }
      ...>    }
      ...>  },
      ...>  previous_public_key: "00EE9EBD56635EFA6C6382747CEC9B4B7E52B3E3CFF8B7A16077AC47E48EC06D38",
      ...>  previous_signature: "4DB9FF771458F8DBCB8CC18101DFF133E60BF99B0A09C25275422B0787BA6597C567F7F27D21D55FE1B211798F17543A7466D27F2F11CD64D802E526AAC19E06",
      ...>  origin_signature: "DA9252B7B0975B4208C80008817D9CE3F8BC7E3785D3CF3175D4BA248A55220F838F19742285A5F397F3350A8BFF779FB3F58AC078D4904557C973CEAE490904"
      ...> }
      iex> nodes = [
      ...>  %{ last_public_key: "000448BC58AB745FE9099A774F9A0AD8243A7519429D5E3103040E634D9CF25DB7", geo_patch: "A09", availability: 1},
      ...>  %{ last_public_key: "00EBE80B7CADEA277AC05FB85C7164FE15EBD6873C4A74B3296A462A1026FD9B0F", geo_patch: "B22", availability: 0},
      ...>  %{ last_public_key: "0050C4A5871AD3379F2879D12CEF750D1211633283A9C3730238E6DDF084DB4C8A", geo_patch: "CED", availability: 0},
      ...>  %{ last_public_key: "008461A06F7C3C0CF1111AD70DA871BA9B00FFB601073E7B5705DFABCFAD043CD5", geo_patch: "F24", availability: 0},
      ...>  %{ last_public_key: "0097EB816A49B0475B783FF50033F8348FF7D40570AA5AB5347BB8D04BF7909870", geo_patch: "AA8", availability: 1},
      ...>  %{ last_public_key: "00B0AAED00758B90D8EB5ACC641F6F6CE3BCEBE9E5A378B67AF1B54E78335358C5", geo_patch: "D7C", availability: 1},
      ...>  %{ last_public_key: "005434F7A2BF3DAC47304180E9E8A756C2C4A733D5160A911A1A2C85438EB1FD7B", geo_patch: "BCF", availability: 1},
      ...>  %{ last_public_key: "0025974DE26089481B49416CBFA2CB9EAA7E10C68FFA48A5FFD03985BACA9A4BCA", geo_patch: "AC1", availability: 1},
      ...>  %{ last_public_key: "0031559D7941C3C9A82EA05CB0D5E80BC90F06EA4925DC81EF320DF55D6186F0B6", geo_patch: "EE2", availability: 1},
      ...>  %{ last_public_key: "007584B83DF6E968128EF701BF66FE298C8AE8ECEEA504BF7AFD0D62347E255CB4", geo_patch: "CEA", availability: 1}
      ...>]
      iex> UnirisElection.validation_nodes(tx, nodes, "8D9CF35197A7AAD1A583C448A91633A002ED3401AD637D795C057F9B0E113478")
      [
        %{availability: 1, geo_patch: "A09", last_public_key: "000448BC58AB745FE9099A774F9A0AD8243A7519429D5E3103040E634D9CF25DB7"},
        %{availability: 1, geo_patch: "D7C", last_public_key: "00B0AAED00758B90D8EB5ACC641F6F6CE3BCEBE9E5A378B67AF1B54E78335358C5"},
        %{availability: 1, geo_patch: "BCF", last_public_key: "005434F7A2BF3DAC47304180E9E8A756C2C4A733D5160A911A1A2C85438EB1FD7B"},
        %{availability: 1, geo_patch: "EE2", last_public_key: "0031559D7941C3C9A82EA05CB0D5E80BC90F06EA4925DC81EF320DF55D6186F0B6"},
        %{availability: 1, geo_patch: "CEA", last_public_key: "007584B83DF6E968128EF701BF66FE298C8AE8ECEEA504BF7AFD0D62347E255CB4"}
      ]
  """
  @spec validation_nodes(
          UnirisChain.Transaction.pending(),
          [Node.t()],
          binary,
          constraints :: [
            min_geo_patch: (() -> non_neg_integer()),
            validation_number: (Transaction.pending() -> non_neg_integer())
          ]
        ) :: [Node.t()]
  def validation_nodes(
        tx = %Transaction{},
        nodes,
        daily_nonce,
        constraints \\ [
          min_geo_patch: fn -> Constraints.min_validation_geo_patch() end,
          validation_number: fn tx = %Transaction{} -> Constraints.validation_number(tx) end
        ]
      )
      when is_binary(daily_nonce) and is_list(nodes) and length(nodes) >= 5 do
    # Evaluate heuristics constraints
    min_geo_patch = Keyword.get(constraints, :min_geo_patch).()
    nb_validations = Keyword.get(constraints, :validation_number).(tx)

    nodes
    |> sort_nodes_by_key_rotation(:last_public_key, daily_nonce, Crypto.hash(tx))
    |> Enum.filter(&(&1.availability == 1))
    |> case do
      nodes when length(nodes) < nb_validations ->
        {:error, :unsufficient_network}

      nodes ->
        nodes
        |> Enum.reduce_while(%{nodes: [], zones: []}, fn n, acc ->
          reduce_validation_node_election(n, acc,
            nb_validations: nb_validations,
            min_geo_patch: min_geo_patch
          )
        end)
        |> Map.get(:nodes)
        |> case do
          elected_nodes when length(elected_nodes) < nb_validations ->
            {:error, :unsufficient_network}

          elected_nodes ->
            elected_nodes
        end
    end
  end

  @spec reduce_validation_node_election(
          Node.t(),
          %{zones: map(), nodes: list(Node.t())},
          nb_validations: non_neg_integer(),
          min_geo_patch: non_neg_integer()
        ) :: %{zones: list(), nodes: list(Node.t())}
  defp reduce_validation_node_election(
         n,
         acc,
         nb_validations: nb_validations,
         min_geo_patch: min_geo_patch
       ) do
    if length(acc.zones) >= min_geo_patch and length(acc.nodes) >= nb_validations do
      {:halt, acc}
    else
      top_geo_patch = String.first(n.geo_patch)

      case Enum.find(acc.zones, &(&1 == top_geo_patch)) do
        nil ->
          {:cont,
           acc
           |> Map.update!(:nodes, &(&1 ++ [n]))
           |> Map.update!(:zones, &(&1 ++ [top_geo_patch]))}

        _ ->
          {:cont, acc}
      end
    end
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


  iex> nodes = [
  ...>  %{ first_public_key: "000448BC58AB745FE9099A774F9A0AD8243A7519429D5E3103040E634D9CF25DB7", geo_patch: "A09", availability: 1, average_availability: 0.8 },
  ...>  %{ first_public_key: "00EBE80B7CADEA277AC05FB85C7164FE15EBD6873C4A74B3296A462A1026FD9B0F", geo_patch: "B22", availability: 0, average_availability: 0.7},
  ...>  %{ first_public_key: "0050C4A5871AD3379F2879D12CEF750D1211633283A9C3730238E6DDF084DB4C8A", geo_patch: "CED", availability: 0, average_availability: 0.6},
  ...>  %{ first_public_key: "008461A06F7C3C0CF1111AD70DA871BA9B00FFB601073E7B5705DFABCFAD043CD5", geo_patch: "F24", availability: 0, average_availability: 0.1},
  ...>  %{ first_public_key: "0097EB816A49B0475B783FF50033F8348FF7D40570AA5AB5347BB8D04BF7909870", geo_patch: "AA8", availability: 1, average_availability: 0.8},
  ...>  %{ first_public_key: "00B0AAED00758B90D8EB5ACC641F6F6CE3BCEBE9E5A378B67AF1B54E78335358C5", geo_patch: "D7C", availability: 1, average_availability: 0.5},
  ...>  %{ first_public_key: "005434F7A2BF3DAC47304180E9E8A756C2C4A733D5160A911A1A2C85438EB1FD7B", geo_patch: "BCF", availability: 1, average_availability: 1},
  ...>  %{ first_public_key: "0025974DE26089481B49416CBFA2CB9EAA7E10C68FFA48A5FFD03985BACA9A4BCA", geo_patch: "AC1", availability: 1, average_availability: 0.4},
  ...>  %{ first_public_key: "0031559D7941C3C9A82EA05CB0D5E80BC90F06EA4925DC81EF320DF55D6186F0B6", geo_patch: "EE2", availability: 1, average_availability: 0.1},
  ...>  %{ first_public_key: "007584B83DF6E968128EF701BF66FE298C8AE8ECEEA504BF7AFD0D62347E255CB4", geo_patch: "CEA", availability: 1, average_availability: 0.2}
  ...>]
  iex> UnirisElection.storage_nodes("0489F19A241A5BA435CBD533EFA4D446696873030DA0B55BC64C6EF0184AA2F6", nodes, "70C371CB8CCA8D3D19C33C8E4FF43C07F155CDA647840E20074B182B4F083CD2")
  [
    %{availability: 1, average_availability: 0.8, first_public_key: "0097EB816A49B0475B783FF50033F8348FF7D40570AA5AB5347BB8D04BF7909870", geo_patch: "AA8"},
    %{availability: 1, average_availability: 0.2, first_public_key: "007584B83DF6E968128EF701BF66FE298C8AE8ECEEA504BF7AFD0D62347E255CB4", geo_patch: "CEA"},
    %{availability: 1, average_availability: 1, first_public_key: "005434F7A2BF3DAC47304180E9E8A756C2C4A733D5160A911A1A2C85438EB1FD7B", geo_patch: "BCF"},
    %{availability: 1, average_availability: 0.1, first_public_key: "0031559D7941C3C9A82EA05CB0D5E80BC90F06EA4925DC81EF320DF55D6186F0B6", geo_patch: "EE2"},
    %{availability: 1, average_availability: 0.8, first_public_key: "000448BC58AB745FE9099A774F9A0AD8243A7519429D5E3103040E634D9CF25DB7", geo_patch: "A09"},
    %{availability: 1, average_availability: 0.5, first_public_key: "00B0AAED00758B90D8EB5ACC641F6F6CE3BCEBE9E5A378B67AF1B54E78335358C5", geo_patch: "D7C"},
    %{availability: 1, average_availability: 0.4, first_public_key: "0025974DE26089481B49416CBFA2CB9EAA7E10C68FFA48A5FFD03985BACA9A4BCA", geo_patch: "AC1"}
  ]
  """
  @spec storage_nodes(
          binary(),
          [Node.t()],
          binary(),
          constraints :: [
            min_geo_patch: (() -> non_neg_integer()),
            min_geo_patch_avg_availability: (() -> non_neg_integer()),
            number_replicas: (nonempty_list(Node.t()) -> non_neg_integer())
          ]
        ) :: [Node.t()]
  def storage_nodes(
        address,
        nodes,
        storage_nonce,
        constraints \\ [
          min_geo_patch: fn -> Constraints.min_storage_geo_patch() end,
          min_geo_patch_avg_availability: fn ->
            Constraints.min_storage_geo_patch_avg_availability()
          end,
          number_replicas: fn nodes -> Constraints.number_replicas(nodes) end
        ]
      )
      when is_binary(address) and is_binary(storage_nonce) and is_list(nodes) and
             is_list(constraints) do
    # Sort nodes using their first public key, the storage nonce and the transaction address
    sorted_nodes = sort_nodes_by_key_rotation(nodes, :first_public_key, storage_nonce, address)

    # Evaluate heuristics constraints
    nb_replicas = Keyword.get(constraints, :number_replicas).(sorted_nodes)
    min_geo_patch = Keyword.get(constraints, :min_geo_patch).()
    min_geo_patch_avg_availability = Keyword.get(constraints, :min_geo_patch_avg_availability).()

    sorted_nodes
    |> Enum.filter(&(&1.availability == 1))
    |> Enum.reduce_while(%{nodes: [], zones: %{}}, fn n, acc ->
      reduce_storage_node_election(n, acc,
        nb_replicas: nb_replicas,
        min_geo_patch: min_geo_patch,
        min_geo_patch_avg_availability: min_geo_patch_avg_availability
      )
    end)
    |> Map.get(:nodes)
  end

  @spec reduce_storage_node_election(
          Node.t(),
          %{zones: map(), nodes: nonempty_list(Node.t())},
          nb_replicas: (nonempty_list(Node.t()) -> non_neg_integer()),
          min_geo_patch: (() -> non_neg_integer()),
          min_geo_patch_avg_availability: (() -> non_neg_integer())
        ) :: %{zones: map(), nodes: list(Node.t())}
  defp reduce_storage_node_election(
         n,
         acc,
         _constraints = [
           nb_replicas: nb_replicas,
           min_geo_patch: min_geo_patch,
           min_geo_patch_avg_availability: min_geo_patch_avg_availability
         ]
       ) do
    sufficient_zones =
      Enum.count(acc.zones, fn {_, cumul} -> cumul >= min_geo_patch_avg_availability end)

    if sufficient_zones >= min_geo_patch and length(acc.nodes) >= nb_replicas do
      {:halt, acc}
    else
      {
        :cont,
        acc
        |> Map.update!(:nodes, &(&1 ++ [n]))
        |> Map.update!(:zones, fn z ->
          Map.update(
            z,
            String.first(n.geo_patch),
            n.average_availability,
            &(&1 + n.average_availability)
          )
        end)
      }
    end
  end

  # To provide an unpredictable and reproducible list of allowed nodes,
  # a rotating key algorithm aims to get a scheduling to be able to
  # find autonomously the validation or storages node involved.
  #
  # Each node public key is rotated through a cryptographic operations involving
  # node public key, a nonce and a dynamic information such as transaction content or hash
  # This rotated key acts as sort mechanism to produce a fair node election
  @spec sort_nodes_by_key_rotation(list(Node.t()), atom(), binary(), binary()) :: list(Node.t())
  defp sort_nodes_by_key_rotation(nodes, key, nonce, hash) do
    nodes
    |> Enum.map(fn n ->
      rotated_key = Crypto.hash(Map.get(n, key) <> "," <> nonce <> "," <> hash)
      {rotated_key, n}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end
end
