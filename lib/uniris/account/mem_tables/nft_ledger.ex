defmodule Uniris.Account.MemTables.NFTLedger do
  @moduledoc false

  @ledger_table :uniris_nft_ledger
  @unspent_output_index_table :uniris_nft_unspent_output_index

  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionInput

  use GenServer

  require Logger

  @doc """
  Initialize the NFT ledger tables:
  - Main NFT ledger as ETS set ({nft, to, from}, amount, spent?)
  - NFT Unspent Output Index as ETS bag (to, {from, nft})

  ## Examples

      iex> {:ok, _} = NFTLedger.start_link()
      iex> { :ets.info(:uniris_nft_ledger)[:type], :ets.info(:uniris_nft_unspent_output_index)[:type] }
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

      iex> {:ok, _pid} = NFTLedger.start_link()
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> { :ets.tab2list(:uniris_nft_ledger), :ets.tab2list(:uniris_nft_unspent_output_index) }
      {
        [
          {{"@Alice2", "@Bob3", "@NFT1"}, 3.0, false, ~U[2021-03-05 13:41:34Z]},
          {{"@Alice2", "@Charlie10", "@NFT1"}, 1.0, false, ~U[2021-03-05 13:41:34Z]}
        ],
        [
          {"@Alice2", "@Bob3", "@NFT1"},
          {"@Alice2", "@Charlie10", "@NFT1"}
        ]
      }

  """
  @spec add_unspent_output(binary(), UnspentOutput.t(), DateTime.t()) :: :ok
  def add_unspent_output(
        to_address,
        %UnspentOutput{
          from: from_address,
          amount: amount,
          type: {:NFT, nft_address}
        },
        timestamp = %DateTime{}
      )
      when is_binary(to_address) and is_binary(from_address) and is_float(amount) and
             is_binary(nft_address) do
    true =
      :ets.insert(
        @ledger_table,
        {{to_address, from_address, nft_address}, amount, false, timestamp}
      )

    true = :ets.insert(@unspent_output_index_table, {to_address, from_address, nft_address})
    :ok
  end

  @doc """
  Get the unspent outputs for a given transaction address

  ## Examples

      iex> {:ok, _pid} = NFTLedger.start_link()
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> NFTLedger.get_unspent_outputs("@Alice2")
      [
        %UnspentOutput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}},
        %UnspentOutput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}},
      ]

      iex> {:ok, _pid} = NFTLedger.start_link()
      iex> NFTLedger.get_unspent_outputs("@Alice2")
      []
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from, nft_address}, acc ->
      case :ets.lookup(@ledger_table, {address, from, nft_address}) do
        [{_, amount, false, _}] ->
          [
            %UnspentOutput{
              from: from,
              amount: amount,
              type: {:NFT, nft_address}
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

      iex> {:ok, _pid} = NFTLedger.start_link()
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.spend_all_unspent_outputs("@Alice2")
      iex> NFTLedger.get_unspent_outputs("@Alice2")
      []

  """
  @spec spend_all_unspent_outputs(binary()) :: :ok
  def spend_all_unspent_outputs(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.each(fn {_, from, nft_address} ->
      :ets.update_element(@ledger_table, {address, from, nft_address}, {3, true})
    end)

    :ok
  end

  @doc """
  Retrieve the entire inputs for a given address (spent or unspent)

  ## Examples

      iex> {:ok, _pid} = NFTLedger.start_link()
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> NFTLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}, spent?: false, timestamp: ~U[2021-03-05 13:41:34Z]},
        %TransactionInput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}, spent?: false, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]

      iex> {:ok, _pid} = NFTLedger.start_link()
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.add_unspent_output("@Alice2", %UnspentOutput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}}, ~U[2021-03-05 13:41:34Z])
      iex> :ok = NFTLedger.spend_all_unspent_outputs("@Alice2")
      iex> NFTLedger.get_inputs("@Alice2")
      [
        %TransactionInput{from: "@Bob3", amount: 3.0, type: {:NFT, "@NFT1"}, spent?: true, timestamp: ~U[2021-03-05 13:41:34Z]},
        %TransactionInput{from: "@Charlie10", amount: 1.0, type: {:NFT, "@NFT1"}, spent?: true, timestamp: ~U[2021-03-05 13:41:34Z]}
      ]
  """
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.map(fn {_, from, nft_address} ->
      [{_, amount, spent?, timestamp}] = :ets.lookup(@ledger_table, {address, from, nft_address})

      %TransactionInput{
        from: from,
        amount: amount,
        type: {:NFT, nft_address},
        spent?: spent?,
        timestamp: timestamp
      }
    end)
  end
end
