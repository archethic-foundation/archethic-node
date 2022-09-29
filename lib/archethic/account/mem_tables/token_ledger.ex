defmodule Archethic.Account.MemTables.TokenLedger do
  @moduledoc false

  @ledger_table :archethic_token_ledger
  @unspent_output_index_table :archethic_token_unspent_output_index

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  use GenServer

  require Logger

  @doc """
  Initialize the Token ledger tables:
  - Main Token ledger as ETS set ({token, to, from, token_id}, amount, spent?)
  - Token Unspent Output Index as ETS bag (to, {from, token, token_id})
  """
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    Logger.info("Initialize InMemory Token Ledger...")

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

      iex> {:ok, _pid} = TokenLedger.start_link()
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}}, ~U[2021-03-05 13:41:34Z])
      iex> { :ets.tab2list(:archethic_token_ledger), :ets.tab2list(:archethic_token_unspent_output_index) }
      {
        [
          {{"@Alice2", "@Bob3", "@Token1", 0}, 300_000_000, false, ~U[2021-03-05 13:41:34Z]},
          {{"@Alice2", "@Charlie10", "@Token1", 1}, 100_000_000, false, ~U[2021-03-05 13:41:34Z]}
        ],
        [
          {"@Alice2", "@Bob3", "@Token1", 0},
          {"@Alice2", "@Charlie10", "@Token1", 1}
        ]
      }

  """
  @spec add_unspent_output(binary(), UnspentOutput.t(), DateTime.t()) :: :ok
  def add_unspent_output(
        to_address,
        %UnspentOutput{
          from: from_address,
          amount: amount,
          type: {:token, token_address, token_id}
        },
        timestamp = %DateTime{}
      )
      when is_binary(to_address) and is_binary(from_address) and is_integer(amount) and amount > 0 and
             is_binary(token_address) and is_integer(token_id) and token_id >= 0 do
    spent? =
      case :ets.lookup(@unspent_output_index_table, to_address) do
        [] ->
          false

        [ledger_key | _] ->
          :ets.lookup_element(@ledger_table, ledger_key, 3)
      end

    true =
      :ets.insert(
        @ledger_table,
        {{to_address, from_address, token_address, token_id}, amount, spent?, timestamp}
      )

    true =
      :ets.insert(
        @unspent_output_index_table,
        {to_address, from_address, token_address, token_id}
      )

    Logger.info(
      "#{amount} unspent Token (#{Base.encode16(token_address)}) added for #{Base.encode16(to_address)}",
      transaction_address: Base.encode16(from_address)
    )

    :ok
  end

  @doc """
  Get the unspent outputs for a given transaction address

  ## Examples

      iex> {:ok, _pid} = TokenLedger.start_link()
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}}, ~U[2021-03-05 13:41:34Z])
      iex> TokenLedger.get_unspent_outputs("@Alice2")
      [
        %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}},
        %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}}
      ]

      iex> {:ok, _pid} = TokenLedger.start_link()
      iex> TokenLedger.get_unspent_outputs("@Alice2")
      []
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from, token_address, token_id}, acc ->
      case :ets.lookup(@ledger_table, {address, from, token_address, token_id}) do
        [{_, amount, false, _}] ->
          [
            %UnspentOutput{
              from: from,
              amount: amount,
              type: {:token, token_address, token_id}
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

      iex> {:ok, _pid} = TokenLedger.start_link()
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1",0}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1",1}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.spend_all_unspent_outputs("@Alice2")
      iex> TokenLedger.get_unspent_outputs("@Alice2")
      []

  """
  @spec spend_all_unspent_outputs(binary()) :: :ok
  def spend_all_unspent_outputs(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.each(fn {_, from, token_address, token_id} ->
      :ets.update_element(@ledger_table, {address, from, token_address, token_id}, {3, true})
    end)

    :ok
  end

  @doc """
  Retrieve the entire inputs for a given address (spent or unspent)

  ## Examples

      iex> {:ok, _pid} = TokenLedger.start_link()
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}}, ~U[2021-03-05 13:41:34Z])
      iex> TokenLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}, spent?: false, timestamp: ~U[2021-03-05 13:41:34Z]},
        %TransactionInput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}, spent?: false, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]

      iex> {:ok, _pid} = TokenLedger.start_link()
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = TokenLedger.spend_all_unspent_outputs("@Alice2")
      iex> TokenLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 300_000_000, type: {:token, "@Token1", 0}, spent?: true, timestamp: ~U[2021-03-05 13:41:34Z]},
        %TransactionInput{from: "@Charlie10", amount: 100_000_000, type: {:token, "@Token1", 1}, spent?: true, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]
  """
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.map(fn {_, from, token_address, token_id} ->
      [{_, amount, spent?, timestamp}] =
        :ets.lookup(@ledger_table, {address, from, token_address, token_id})

      %TransactionInput{
        from: from,
        amount: amount,
        type: {:token, token_address, token_id},
        spent?: spent?,
        timestamp: timestamp
      }
    end)
  end
end
