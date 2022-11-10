defmodule Archethic.SelfRepair.Notifier.RepairWorker do
  @moduledoc false
  use GenStateMachine, callback_mode: [:handle_event_function], restart: :temporary

  alias Archethic.{
    SelfRepair.Notifier
  }

  require Logger

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts, [])
  end

  def init(args) do
    Registry.register(Notifier.Impl.registry_name(), args.genesis_address, [])
    Logger.debug("RepairWorker: Repair Started", address: args.genesis_address)

    # IO.inspect(binding(), label: "0-> init")

    data = %{
      genesis_address: args.genesis_address,
      addresses: [args.last_address]
    }

    new_data = repair_task(data)

    {:ok, :idle, new_data, []}
  end

  def handle_event(:info, {:DOWN, _ref, :process, pid, _normal}, :idle, data) do
    # IO.inspect(binding(), label: "2 :down event -> :idle")

    {_, data} = Map.pop(data, pid)

    {:next_state, :ack_req, data, [{:next_event, :internal, :process_update_requests}]}
  end

  def handle_event(
        :internal,
        :process_update_requests,
        :ack_req,
        data = %{addresses: address_list}
      ) do
    case address_list do
      [] ->
        Logger.debug("Done processing Requests", server_data: data)
        # IO.inspect(binding(), label: "4: terminateing")

        :stop

      x when is_list(x) ->
        new_data = repair_task(data)
        # IO.inspect(binding(), label: "3: :process_update_requests,:ack_req")
        {:next_state, :idle, new_data, []}
    end
  end

  def handle_event(
        :cast,
        {:update_request,
         %{
           last_address: address
         }},
        _,
        data = %{
          addresses: address_list
        }
      ) do
    # IO.inspect(binding(), label: "update request")

    {:keep_state, %{data | addresses: [address | address_list]}, []}
  end

  def handle_event(:info, {_, {:continue, _}}, _s, _data) do
    # IO.inspect(label: "--- nil")
    :keep_state_and_data
  end

  def repair_task(data = %{addresses: address_list, genesis_address: genesis_address}) do
    [repair_addr | new_address_list] = address_list

    %Task{
      pid: pid
    } =
      Task.async(fn ->
        # IO.inspect(binding(), label: "1: repair_task")
        {:continue, _} = Notifier.Impl.repair_chain(repair_addr, genesis_address)
      end)

    data
    |> Map.put(:addresses, new_address_list)
    |> Map.put(pid, nil)
  end
end
