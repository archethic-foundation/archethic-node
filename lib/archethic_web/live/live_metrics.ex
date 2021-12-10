defmodule ArchEthicWeb.LiveMetrics do
  @moduledoc false

  # alias TelemetryMetricsPrometheus.Core
  use Phoenix.LiveView
  use Phoenix.HTML


  def mount(_params, _session, socket) do
    if connected?(socket) do
        :timer.send_interval(1800, self(), :update)
    end
    {:ok, socket}
  end

  @spec render(any) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~L"""
         <h2>Node.Metric </h2>

         <div style="display:flex">
              <div id='echartContainer1'  phx-hook='echart1' style="width: 545px; height: 224px" >
              <canvas id="echartDiv"  phx-update='ignore' ></canvas>
              </div >
              <div id='echartContainer2'  phx-hook='echart1' style="width: 545px; height: 224px" >
              <canvas id="echartDiv"  phx-update='ignore' ></canvas>
              </div >

         </div >

         <div style="display:flex">
         <div id='echartContainer3'  phx-hook='echart1' style="width: 545px; height: 224px" >
         <canvas id="echartDiv"  phx-update='ignore' ></canvas>
         </div >
         <div id='echartContainer4'  phx-hook='echart1' style="width: 545px; height: 224px" >
         <canvas id="echartDiv"  phx-update='ignore' ></canvas>
         </div >

    </div >



    """
  end


  def handle_info(:update, socket) do


        {:noreply, socket |> push_event("points", %{ points:  get_points()})}
  end

  def get_points() do

    Enum.map(  1..7,fn _ -> :rand.uniform(100)end)

    end


  # def get_new_metrics() do
  #   metrics = Core.scrape()
  #   metrics = ArchEthic.Metrics.MetricsDataParser.run(metrics)
  #   IO.inspect metrics
  #    IO.inspect "Inside=====================parsing"
  #   [_one,_two,_three,_four,_five,_six,_seven,_eight,_nine,_ten,_eleven,_tweleve,_thirteen,_fourteen,_fifteen,election_validation,election_storage,_pow,_nineteen,_full_txn_validation,_contract_parsing,_twentytwo,_twentythree] = metrics

  #      [
  #        destructure_data_n_get_average(election_validation),
  #        destructure_data_n_get_average(election_storage)
  #      ]

  # end

  # @spec destructure_data_n_get_average(nil | maybe_improper_list | map) :: float
  # def destructure_data_n_get_average(data)do
  #   [a] = data[:metrics]
  #   {sum,_} = Float.parse(a["sum"])
  #   {count,_} = Float.parse(a["count"])
  #    sum / count
  # end




  # def get_metrics()do
  #     scrapped_metrics = Core.scrape()
  #   metric_parse = ArchEthic.Metrics.MetricsDataParser.run(scrapped_metrics)
  #   parsed_data = Enum.filter(metric_parse, filter_data())
  #   IO.inspect(parsed_data)

  #   [election_validation_nodes,
  #    election_storage_nodes,
  #    mining_pending_transaction_validation,
  #   mining_proof_of_work_duration,
  #   mining_full_transaction_validation,
  #   contract_parsing_duration]=parsed_data

  #   temp=[
  #     destructure_data_n_get_average(election_validation_nodes),
  #     destructure_data_n_get_average(election_storage_nodes),
  #     destructure_data_n_get_average(mining_pending_transaction_validation ),
  #     destructure_data_n_get_average(mining_proof_of_work_duration),
  #     destructure_data_n_get_average(mining_full_transaction_validation),
  #     destructure_data_n_get_average(contract_parsing_duration)
  #   ]
  #   IO.inspect temp

  #   # for data <- parsed_data do
  #   #       %{metrics: metric_data} = data
  #   #       IO.inspect metric_data
  #   #       put_in(final_avg,data.name,%{})
  #   #       for in_data<-metric_data do
  #   #         IO.inspect in_data
  #           # final_avg++[acuurent_avg]
  #   #       end

  #   #  end
  # end

  #   def filter_data() do
  #     fn
  #        %{metrics: _, name: "archethic_election_validation_nodes_duration", type: _} -> true
  #        %{metrics: _, name: "archethic_election_storage_nodes_duration", type: _} -> true
  #        %{metrics: _, name: "archethic_mining_pending_transaction_validation_duration", type: _} -> true
  #        %{metrics: _, name: "archethic_mining_proof_of_work_duration", type: _} -> true
  #        %{metrics: _, name: "archethic_mining_full_transaction_validation_duration", type: _} -> true
  #        %{metrics: _, name: "archethic_contract_parsing_duration", type: _} -> true
  #        %{metrics: _, name: _, type: _} -> false
  #      end
  #  end

  #  def destructure_data_n_get_average(data)do
  #   [a] = data[:metrics]
  #   {sum,_} = Float.parse(a["sum"])
  #   {count,_} = Float.parse(a["count"])
  #    sum / count
  # end
end
