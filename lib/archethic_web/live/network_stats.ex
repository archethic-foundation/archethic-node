defmodule ArchEthicWeb.NetworkStats do
  @moduledoc false

  use Phoenix.LiveView
  use Phoenix.HTML

  def mount(_params, _session, socket) do
    if connected?(socket) do
      ArchEthic.Metrics.MetricClient.monitor()
      :timer.send_interval(5_000, self(), :update)
    end

    {:ok, socket}
  end

  def handle_info(:update, socket) do
    data = ArchEthic.Metrics.MetricClient.get_network_points()
    {:noreply, socket |> push_event("network_points", %{points: data})}
  end

  @spec render(any) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~L"""
        <h2 style="user-select: auto; color: #fff;">Network Telemetry</h2>

          <div class="columns is-mobile" style = "display:flex;flex-direction:row;flex-wrap:wrap;">

            <div class="column is-full-mobile is-half-tablet is-half-desktop" >
              <div id="echartContainer0" class="box" phx-hook="network_charts" style="width: 100%; min-height: 200px;">
                <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
            </div>


             <div class="column is-full-mobile is-half-tablet is-half-desktop ">
                 <div id="echartContainer1" class="box" phx-hook="network_charts" style="width: 100%; min-height: 200px;">
                 <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
             </div>



            <div class="column is-full-mobile is-half-tablet is-half-desktop">
               <div id="echartContainer2" class="box" phx-hook="network_charts" style="width: 100%; min-height: 200px;">
               <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
            </div>

           <div class="column is-full-mobile is-half-tablet is-half-desktop ">
            <div id="echartContainer3" class="box" phx-hook="network_charts" style="width: 100%; min-height: 200px;">
            <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
           </div>

          <div class="column is-full-mobile is-half-tablet is-half-desktop ">
            <div id="echartContainer4" class="box" phx-hook="network_charts" style="width: 100%; min-height: 200px;">
            <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
         </div>

         <div class="column is-full-mobile is-half-tablet is-half-desktop ">
          <div id="echartContainer5" class="box" phx-hook="network_charts" style="width: 100%; min-height: 200px">
            <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
        </div>
       </div>



    """
  end
end
