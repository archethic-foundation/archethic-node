defmodule ArchEthicWeb.NetworkMetricsLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """

  use Phoenix.LiveView
  use Phoenix.HTML

  def mount(_params, _session, socket) do
    if connected?(socket) do
      ArchEthic.Metrics.Poller.monitor()
    end

    {:ok, socket}
  end

  def handle_info({:update_data, data}, socket) do
    {:noreply, socket |> push_event("network_points", %{points: data})}
  end

  def render(assigns) do
    ~L"""

          <h2 style="font-size: 40px; color: #fff;">Network Telemetry</h2>
              <br><br>

         <div class="columns" style="justify-content: space-evenly">
            <div class ="column  is-4">
                    <div id='tps' phx-hook='network_charts' style="width: 100%; height: 300px" class= "box">
                    <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 250px">
                    </canvas>
                    </div>
            </div>
            <div class ="column  is-4" >
                  <div id='archethic_p2p_send_message_duration'  phx-hook='network_charts'
                  style="width: 100%; height: 300px" class= "box">
                  <canvas id="echartDiv"   phx-update='ignore' style="width: 100%; min-height: 250px">
                   </canvas></div>
            </div>
         </div>


        <div class="columns " style ="display:flex;flex-direction:row;flex-wrap:wrap;
        justify-content: space-evenly;">

                    <div class="column is-full-mobile is-half-tablet is-5">
                    <div id='archethic_mining_proof_of_work_duration'  class="box" phx-hook='network_charts' style="width: 100%; height: 300px" >
                    <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px">  </canvas>   </div >
                  </div >
            <div class="column is-full-mobile is-half-tablet is-5">
              <div id='archethic_mining_full_transaction_validation_duration' class="box" phx-hook='network_charts' style="width: 100%; height: 300px" >
              <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px"> </canvas> </div>
      </div>

    """
  end
end
