defmodule ArchEthic.Account.MemTables.UCOLedger do
  @moduledoc false

  @ledger_table :archethic_uco_ledger
  @unspent_output_index_table :archethic_uco_unspent_output_index

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionChain.TransactionInput

  use GenServer

  require Logger

  @doc """
  Initialize the UCO ledger tables:
  - Main UCO ledger as ETS set ({to, from}, amount, spent?)
  - UCO Unspent Output Index as ETS bag (to, from)

  ## Examples

      iex> {:ok, _} = UCOLedger.start_link()
      iex> { :ets.info(:archethic_uco_ledger)[:type], :ets.info(:archethic_uco_unspent_output_index)[:type] }
      { :set, :bag }
  """
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> { :ets.tab2list(:archethic_uco_ledger), :ets.tab2list(:archethic_uco_unspent_output_index) }
      {
        [
          {{"@Alice2", "@Bob3"}, 300_000_000, false, ~U[2021-03-05 13:41:34Z], false},
          {{"@Alice2", "@Charlie10"}, 100_000_000, false, ~U[2021-03-05 13:41:34Z], false}
       ],
        [
          {"@Alice2", "@Bob3"},
          {"@Alice2", "@Charlie10"}
        ]
      }

  """
  @spec add_unspent_output(binary(), UnspentOutput.t(), DateTime.t()) :: :ok
  def add_unspent_output(
        to,
        %UnspentOutput{from: from, amount: amount, reward?: reward?},
        timestamp = %DateTime{}
      )
      when is_binary(to) and is_integer(amount) and amount > 0 do
    true = :ets.insert(@ledger_table, {{to, from}, amount, false, timestamp, reward?})
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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> UCOLedger.get_unspent_outputs("@Alice2")
      [
        %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO},
        %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO},
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
        [{_, amount, false, _, reward?}] ->
          [
            %UnspentOutput{
              from: from,
              amount: amount,
              type: :UCO,
              reward?: reward?
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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> UCOLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 300_000_000, spent?: false, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z]},
        %TransactionInput{from: "@Charlie10", amount: 100_000_000, spent?: false, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.spend_all_unspent_outputs("@Alice2")
      iex> UCOLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 300_000_000, spent?: true, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z] },
        %TransactionInput{from: "@Charlie10", amount: 100_000_000, spent?: true, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z]}
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
