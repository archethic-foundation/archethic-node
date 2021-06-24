defmodule ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement do
  @moduledoc """
  Represents the movements regarding the nodes involved during the
  transaction validation. The node public keys are present as well as their rewards
  """
  defstruct [:to, :amount, :roles]

  alias ArchEthic.Crypto

  @type role() ::
          :coordinator_node | :cross_validation_node | :previous_storage_node

  @type t() :: %__MODULE__{
          to: Crypto.key(),
          amount: float(),
          roles: list(role())
        }

  @doc """
  Serialize a node movement into binary format

  ## Examples

      iex> %NodeMovement{
      ...>    to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>    amount: 0.30,
      ...>    roles: [:coordinator_node, :previous_storage_node]
      ...>  }
      ...>  |> NodeMovement.serialize()
      <<
      # Node public key
      0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      # Amount
      63, 211, 51, 51, 51, 51, 51, 51,
      # Nb roles
      2,
      # Coordinator and previous storage node roles
      0, 2
      >>
  """
  @spec serialize(t()) :: <<_::64, _::_*8>>
  def serialize(%__MODULE__{to: to, amount: amount, roles: roles}) do
    roles_bin = Enum.map(roles, &role_to_bin/1) |> :erlang.list_to_binary()
    <<to::binary, amount::float, length(roles)::8, roles_bin::binary>>
  end

  defp role_to_bin(:coordinator_node), do: <<0>>
  defp role_to_bin(:cross_validation_node), do: <<1>>
  defp role_to_bin(:previous_storage_node), do: <<2>>

  @doc """
  Deserialize an encoded node movement

  ## Examples

      iex> <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...> 159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186,
      ...> 63, 211, 51, 51, 51, 51, 51, 51, 2, 0, 2
      ...> >>
      ...> |> NodeMovement.deserialize()
      {
        %NodeMovement{
          to: <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
            159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
          amount: 0.30,
          roles: [:coordinator_node, :previous_storage_node]
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<curve_id::8, origin_id::8, rest::bitstring>>) do
    key_size = Crypto.key_size(curve_id)

    <<key::binary-size(key_size), amount::float, nb_roles::8, bin_roles::binary-size(nb_roles),
      rest::bitstring>> = rest

    {
      %__MODULE__{
        to: <<curve_id::8, origin_id::8, key::binary>>,
        amount: amount,
        roles: bin_roles_to_list(bin_roles)
      },
      rest
    }
  end

  defp bin_roles_to_list(_, acc \\ [])

  defp bin_roles_to_list(<<0, rest::binary>>, acc),
    do: bin_roles_to_list(rest, [:coordinator_node | acc])

  defp bin_roles_to_list(<<1, rest::binary>>, acc),
    do: bin_roles_to_list(rest, [:cross_validation_node | acc])

  defp bin_roles_to_list(<<2, rest::binary>>, acc),
    do: bin_roles_to_list(rest, [:previous_storage_node | acc])

  defp bin_roles_to_list(<<>>, acc), do: Enum.reverse(acc)

  @spec from_map(map()) :: t()
  def from_map(movement = %{}) do
    roles =
      case Map.get(movement, :roles) do
        nil ->
          nil

        roles ->
          Enum.map(roles, &String.to_atom/1)
      end

    %__MODULE__{
      to: Map.get(movement, :to),
      amount: Map.get(movement, :amount),
      roles: roles
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{to: to, amount: amount, roles: roles}) do
    %{
      to: to,
      amount: amount,
      roles: Enum.map(roles, &Atom.to_string/1)
    }
  end
end
