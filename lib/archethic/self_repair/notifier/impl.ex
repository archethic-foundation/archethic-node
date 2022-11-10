defmodule Archethic.SelfRepair.Notifier.Impl do
  @moduledoc false

  alias Archethic.{
    Crypto,
    Election,
    P2P,
    P2P.Node,
    Replication,
    TransactionChain
  }

  alias Archethic.SelfRepair.Notifier.RepairSupervisor
  alias Archethic.SelfRepair.Notifier.RepairWorker
  require Logger

  @registry_name Archethic.SelfRepair.Notifier.RepairRegistry

  @validation_errors Replication.TransactionValidator.list_errors()

  @doc """
  Returns Registry Name used to store pid and genesis_address.
  """
  def registry_name, do: @registry_name

  @doc """
  Update Corresponding worker with new Request message.
  """
  def update_worker(msg, pid) do
    case Process.alive?(pid) do
      true ->
        GenStateMachine.cast(pid, {:update_request, msg})

      false ->
        start_worker(msg)
    end
  end

  @doc """
  Return true if the Chain repair is OnGoing
  """
  @spec repair_in_progress?(genesis_address :: binary()) :: false | pid()
  def repair_in_progress?(genesis_address) do
    case Registry.lookup(@registry_name, genesis_address) do
      [{pid, _}] ->
        pid

      _ ->
        false
    end
  end

  @spec start_worker(map()) :: :ok
  def start_worker(opts) do
    DynamicSupervisor.start_child(
      RepairSupervisor,
      {
        RepairWorker,
        opts
      }
    )

    :ok
  end

  @spec repair_chain(address :: binary(), genesis_address :: binary()) ::
          {:continue, :success | :error | :crash}
  @doc """
  Fetches Last txn and repairs chain via validate_and_store_transaction_chain.A blocking code.
  """
  def repair_chain(address, genesis_address) do
    with false <-
           TransactionChain.transaction_exists?(address),
         {:ok, node_list} <-
           get_nodes(address),
         {:ok, txn} <-
           TransactionChain.fetch_transaction_remotely(address, node_list),
         :ok <-
           Replication.validate_and_store_transaction_chain(txn) do
      log(:debug, "Successfull Repair", genesis_address, address, nil)
      {:continue, :success}
    else
      {:error, e = :empty} ->
        log(:debug, "Election returned empty set, Omitting", genesis_address, address, e)
        {:continue, :error}

      {:error, e} when e in @validation_errors ->
        log(:warning, "Replication returned Validation Error", genesis_address, address, e)
        {:continue, :error}

      {:error, e}
      when e in [:transaction_not_exists, :transaction_invalid, :network_issue] ->
        log(:warning, "Fetch Issue", genesis_address, address, e)
        {:continue, :error}

      {:error, e = :transaction_already_exists} ->
        log(:debug, "", genesis_address, address, e)
        {:continue, :error}

      e ->
        log(:warning, "Unhandled error", genesis_address, address, e)
        {:continue, :error}
    end
  rescue
    e ->
      log(:warning, "Crash during Repair", genesis_address, address, e)
      {:continue, :crash}
  end

  @doc """
  Logger for Repair Process
  """
  def log(type, msg, genesis_address, address, e) do
    gen_addr = Base.encode16(genesis_address)
    last_addr = Base.encode16(address)

    case type do
      :debug ->
        Logger.debug(
          "RepairWorker: Genesis_Address: #{gen_addr}, address: #{last_addr}.#{msg}, Error: #{e}"
        )

      :warning ->
        Logger.warning(
          "RepairWorker: Genesis_Address: #{gen_addr}, address: #{last_addr}.#{msg}, Error: #{e}"
        )
    end

    :ok
  end

  @spec get_nodes(binary) :: {:error, :empty} | {:ok, [Archethic.P2P.Node.t()]}
  def get_nodes(address) do
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())
      # |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)
      |> P2P.unprioritize_node(Crypto.first_node_public_key())

    case nodes do
      [] -> {:error, :empty}
      x when is_list(x) -> {:ok, x}
    end
  end
end
