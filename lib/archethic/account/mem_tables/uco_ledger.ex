defmodule Archethic.Account.MemTables.UCOLedger do
  @moduledoc false

  @ledger_table :archethic_uco_ledger
  @unspent_output_index_table :archethic_uco_unspent_output_index

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  use GenServer

  require Logger

  @doc """
  Initialize the UCO ledger tables:
  - Main UCO ledger as ETS set ({{to, from}, amount, spent?, timestamp, reward?})
  - UCO Unspent Output Index as ETS bag (to, from)
  """
  @spec start_link(args :: list()) ::
          {:ok, pid()} | {:error, reason :: any()} | {:stop, reason :: any()} | :ignore
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec init(args :: list()) :: {:ok, map()}
  def init(_) do
    Logger.info("Initialize InMemory UCO Ledger...")

    :ets.new(@ledger_table, [:set, :named_table, :public, read_concurrency: true])

    :ets.new(@unspent_output_index_table, [
      :bag,
      :named_table,
      :public,
      read_concurrency: true
    ])

    {:ok,
     %{
       ledger_table: @ledger_table,
       unspent_outputs_index_table: @unspent_output_index_table
     }}
  end

  @doc """
  Add an unspent output to the ledger for the recipient address

  ## Examples

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> { :ets.tab2list(:archethic_uco_ledger), :ets.tab2list(:archethic_uco_unspent_output_index) }
      {
        [
          {{"@Alice2", "@Bob3"}, 300_000_000, false, ~U[2022-10-11 09:24:01.879Z], false},
          {{"@Alice2", "@Charlie10"}, 100_000_000, false, ~U[2022-10-11 09:24:01.879Z], false}
       ],
        [
          {"@Alice2", "@Bob3"},
          {"@Alice2", "@Charlie10"}
        ]
      }

  """
  @spec add_unspent_output(binary(), UnspentOutput.t()) :: :ok
  def add_unspent_output(
        to,
        %UnspentOutput{from: from, amount: amount, reward?: reward?, timestamp: timestamp}
      )
      when is_binary(to) and is_integer(amount) and amount > 0 and not is_nil(timestamp) do
    spent? =
      case :ets.lookup(@unspent_output_index_table, to) do
        [] ->
          false

        [ledger_key | _] ->
          :ets.lookup_element(@ledger_table, ledger_key, 3)
      end

    true = :ets.insert(@ledger_table, {{to, from}, amount, spent?, timestamp, reward?})
    true = :ets.insert(@unspent_output_index_table, {to, from})

    Logger.info("#{amount} unspent UCO added for #{Base.encode16(to)}",
      transaction_address: Base.encode16(from)
    )

    :ok
  end

  @doc """
  Get the unspent outputs for a given transaction address

  ## Examples

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO, timestamp: ~U[2022-10-10 09:27:17.846Z]})
      iex> UCOLedger.get_unspent_outputs("@Alice2")
      [
        %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO,  timestamp: ~U[2022-10-10 09:27:17.846Z] },
        %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]},
       ]

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> UCOLedger.get_unspent_outputs("@Alice2")
      []
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from}, acc ->
      case :ets.lookup(@ledger_table, {address, from}) do
        [{{^address, ^from}, amount, false, timestamp, reward?}] ->
          [
            %UnspentOutput{
              from: from,
              amount: amount,
              type: :UCO,
              reward?: reward?,
              timestamp: timestamp
            }
            | acc
          ]

        _ ->
          acc
      end
    end)
  end

  @doc """
  Spend all the unspent outputs for the given address

  ## Examples

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.spend_all_unspent_outputs("@Alice2")
      iex> UCOLedger.get_unspent_outputs("@Alice2")
      []

  """
  @spec spend_all_unspent_outputs(binary()) :: :ok
  def spend_all_unspent_outputs(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.each(&:ets.update_element(@ledger_table, &1, {3, true}))

    :ok
  end

  @doc """
  Retrieve the entire inputs for a given address (spent or unspent)

  ## Examples

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO, timestamp:  ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> UCOLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 300_000_000, spent?: false, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]},
        %TransactionInput{from: "@Charlie10", amount: 100_000_000, spent?: false, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]}
      ]

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]})
      iex> :ok = UCOLedger.spend_all_unspent_outputs("@Alice2")
      iex> UCOLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 300_000_000, spent?: true, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z] },
        %TransactionInput{from: "@Charlie10", amount: 100_000_000, spent?: true, type: :UCO, timestamp: ~U[2022-10-11 09:24:01.879Z]}
      ]
  """
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.map(fn {_, from} ->
      [{_, amount, spent?, timestamp, reward?}] = :ets.lookup(@ledger_table, {address, from})

      %TransactionInput{
        from: from,
        amount: amount,
        spent?: spent?,
        type: :UCO,
        timestamp: timestamp,
        reward?: reward?
      }
    end)
  end
end
