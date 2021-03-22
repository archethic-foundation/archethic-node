defmodule Uniris.Account.MemTables.UCOLedger do
  @moduledoc false

  @ledger_table :uniris_uco_ledger
  @unspent_output_index_table :uniris_uco_unspent_output_index

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionInput

  use GenServer

  require Logger

  @doc """
  Initialize the UCO ledger tables:
  - Main UCO ledger as ETS set ({to, from}, amount, spent?)
  - UCO Unspent Output Index as ETS bag (to, from)

  ## Examples

      iex> {:ok, _} = UCOLedger.start_link()
      iex> { :ets.info(:uniris_uco_ledger)[:type], :ets.info(:uniris_uco_unspent_output_index)[:type] }
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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> { :ets.tab2list(:uniris_uco_ledger), :ets.tab2list(:uniris_uco_unspent_output_index) }
      {
        [
          {{"@Alice2", "@Charlie10"}, 1.0, false, ~U[2021-03-05 13:41:34Z]},
          {{"@Alice2", "@Bob3"}, 3.0, false, ~U[2021-03-05 13:41:34Z]}
        ],
        [
          {"@Alice2", "@Bob3"},
          {"@Alice2", "@Charlie10"}
        ]
      }

  """
  @spec add_unspent_output(binary(), UnspentOutput.t(), DateTime.t()) :: :ok
  def add_unspent_output(to, %UnspentOutput{from: from, amount: amount}, timestamp = %DateTime{})
      when is_binary(to) and is_float(amount) do
    true = :ets.insert(@ledger_table, {{to, from}, amount, false, timestamp})
    true = :ets.insert(@unspent_output_index_table, {to, from})
    :ok
  end

  @doc """
  Get the unspent outputs for a given transaction address

  ## Examples

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> UCOLedger.get_unspent_outputs("@Alice2")
      [
        %UnspentOutput{from: "@Charlie10", amount: 1.0, type: :UCO},
        %UnspentOutput{from: "@Bob3", amount: 3.0, type: :UCO},
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
        [{_, amount, false, _}] ->
          [
            %UnspentOutput{
              from: from,
              amount: amount,
              type: :UCO
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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
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
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> UCOLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 3.0, spent?: false, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z]},
        %TransactionInput{from: "@Charlie10", amount: 1.0, spent?: false, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]

      iex> {:ok, _pid} = UCOLedger.start_link()
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: :UCO}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = UCOLedger.spend_all_unspent_outputs("@Alice2")
      iex> UCOLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 3.0, spent?: true, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z] },
        %TransactionInput{from: "@Charlie10", amount: 1.0, spent?: true, type: :UCO, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]
  """
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.map(fn {_, from} ->
      [{_, amount, spent?, timestamp}] = :ets.lookup(@ledger_table, {address, from})

      %TransactionInput{
        from: from,
        amount: amount,
        spent?: spent?,
        type: :UCO,
        timestamp: timestamp
      }
    end)
  end
end
