defmodule Uniris.BeaconChain.Subset.SlotRegistry do
  @moduledoc """
  Represents a subset slot registry within current slot and previous sealed slots
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.NodeInfo
  alias Uniris.BeaconChain.Slot.TransactionInfo

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.TransactionData

  alias Uniris.Utils

  defstruct slots: %{}, current_slot: %Slot{}

  @type sealed_slots :: %{(date :: DateTime.t()) => sealed_slots :: Transaction.t()}

  @type t :: %__MODULE__{
          current_slot: Slot.t(),
          slots: sealed_slots()
        }

  @doc """
  Add a transaction info to the current slot

  ## Examples

      iex> %SlotRegistry{}
      ...> |> SlotRegistry.add_transaction_info(%TransactionInfo{
      ...>   address: "@Alice2",
      ...>   timestamp: ~U[2020-09-25 11:26:56.348018Z],
      ...>   type: :transfer,
      ...>   movements_addresses: []
      ...> })
      %SlotRegistry{
        current_slot: %Slot{
          transactions: [
            %TransactionInfo{
              address: "@Alice2",
              timestamp: ~U[2020-09-25 11:26:56.348018Z],
              type: :transfer,
              movements_addresses: []
            }
          ]
        }
      }
  """
  @spec add_transaction_info(__MODULE__.t(), TransactionInfo.t()) :: __MODULE__.t()
  def add_transaction_info(state = %__MODULE__{}, tx_info = %TransactionInfo{}) do
    Map.update!(state, :current_slot, &Slot.add_transaction_info(&1, tx_info))
  end

  @doc """
  Add a node info to the current slot

  ## Examples

      iex> %SlotRegistry{}
      ...> |> SlotRegistry.add_node_info(%NodeInfo{
      ...>   public_key: "NodePub2",
      ...>   timestamp: ~U[2020-09-25 11:26:56.348018Z]
      ...> })
      %SlotRegistry{
        current_slot: %Slot{
          nodes: [
            %NodeInfo{
              public_key: "NodePub2",
              timestamp: ~U[2020-09-25 11:26:56.348018Z]
            }
          ]
        }
      }
  """
  @spec add_node_info(__MODULE__.t(), NodeInfo.t()) :: __MODULE__.t()
  def add_node_info(state = %__MODULE__{}, node_info = %NodeInfo{}) do
    Map.update!(state, :current_slot, &Slot.add_node_info(&1, node_info))
  end

  @doc """
  Determine if the registry contains a transaction info

  ## Examples

      iex> %SlotRegistry{}
      ...> |> SlotRegistry.add_transaction_info(%TransactionInfo{
      ...>   address: "@Alice2",
      ...>   timestamp: ~U[2020-09-25 11:26:56.348018Z],
      ...>   type: :transfer,
      ...>   movements_addresses: []
      ...> })
      ...> |> SlotRegistry.has_transaction?("@Alice2")
      true

      iex> %SlotRegistry{slots: %{
      ...>   ~U[2020-09-25 11:26:56.348018Z] => %Transaction{
      ...>         data: %TransactionData{content: <<0, 0, 0, 1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>           99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12, 94, 244, 190, 185, 2, 0, 0, 0, 1, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>           100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241, 94, 244, 190, 185, 1::1>>}
      ...>      }
      ...>   }
      ...> }
      ...> |> SlotRegistry.has_transaction?(<<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>     99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>)
      true

  """
  @spec has_transaction?(__MODULE__.t(), binary()) :: boolean()
  def has_transaction?(%__MODULE__{current_slot: current_slot, slots: slots}, address) do
    if Slot.has_transaction?(current_slot, address) do
      true
    else
      Enum.any?(slots, fn {_, %Transaction{data: %TransactionData{content: content}}} ->
        {slot, _} = Slot.deserialize(content)
        Slot.has_transaction?(slot, address)
      end)
    end
  end

  @doc """
  Retrieve the slots after a given date from the sealed slots

  The slots returned as sorted from the most recent

  ## Examples

      iex> %SlotRegistry{
      ...>   slots: %{
      ...>      ~U[2020-09-25 11:34:02.992213Z] => %Transaction{
      ...>         data: %TransactionData{content: <<0, 0, 0, 1, 0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
      ...>           99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12, 94, 244, 190, 185, 2, 0, 0, 0, 1, 0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
      ...>           100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241, 94, 244, 190, 185, 1::1>>}
      ...>      }
      ...>   }
      ...> }
      ...> |> SlotRegistry.slots_after(~U[2020-09-25 09:04:02Z])
      [
        %Slot{
          transactions: [
            %TransactionInfo{
               address: <<0, 234, 233, 156, 155, 114, 241, 116, 246, 27, 130, 162, 205, 249, 65, 232, 166,
                 99, 207, 133, 252, 112, 223, 41, 12, 206, 162, 233, 28, 49, 204, 255, 12>>,
               timestamp: ~U[2020-06-25 15:11:53Z],
               type: :transfer,
               movements_addresses: []
            }
          ],
          nodes: [ %NodeInfo{
            public_key: <<0, 38, 105, 235, 147, 234, 114, 41, 1, 152, 148, 120, 31, 200, 255, 174, 190, 91,
             100, 169, 225, 113, 249, 125, 21, 168, 14, 196, 222, 140, 87, 143, 241>>,
            timestamp: ~U[2020-06-25 15:11:53Z],
            ready?: true
          }]
        }
      ]
  """
  @spec slots_after(__MODULE__.t(), DateTime.t()) :: list(Slot.t())
  def slots_after(%__MODULE__{slots: slots}, date = %DateTime{}) do
    slots
    |> Enum.filter(fn {time, _} -> DateTime.compare(time, date) == :gt end)
    |> Enum.sort_by(fn {time, _} -> time end)
    |> Enum.map(fn {_, %Transaction{data: %TransactionData{content: content}}} ->
      {slot, _} = Slot.deserialize(content)
      slot
    end)
  end

  @doc """
  Seal the current slot into a transaction and add it to the slot lists by time.

  The transaction created is built from the beacon chain shared seed
  """
  @spec seal_current_slot(__MODULE__.t(), DateTime.t()) :: __MODULE__.t()
  def seal_current_slot(registry = %__MODULE__{current_slot: current_slot}, time = %DateTime{}) do
    content =
      current_slot
      |> Slot.serialize()
      |> Utils.wrap_binary()

    tx = Transaction.new(:beacon, %TransactionData{content: content})

    registry
    |> Map.put(:current_slot, %Slot{})
    |> Map.update!(:slots, &Map.put(&1, time, tx))
  end
end
