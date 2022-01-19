defmodule ArchEthicWeb.NodeStats do
  @moduledoc false

  use Phoenix.LiveView
  use Phoenix.HTML

  # buffer task async stream
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ArchEthic.Metrics.MetricClient.monitor()
      :timer.send_interval(1800, self(), :update)
    end

    {:ok, socket}
  end

  def handle_info(:update, socket) do
    new_points = ArchEthic.Metrics.MetricClient.get_this_node_points()
    {:noreply, socket |> push_event("node_points", %{points: new_points})}
  end

  @spec render(any) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~L"""

    <h2 style="user-select: auto; color: #fff;"> Nodes Statistics</h2>

            <div class="columns">
            <div class="column">
              <div class="tile is-primary  ">
                    <article class="tile is-child p-4 box has-background-white" >
                        <p class="title has-text-dark">
                      43000000<span class="subtitle has-text-dark">&nbsp(ms)</span>
                  </p>
                  <p style="font-size: 20px;">
                <b>db_duration</b>
                </p>
                </article>
              </div>
            </div>
            <div class="column">
              <div class="tile is-primary  ">
                    <article class="tile is-child p-4 box has-background-white" >
                        <p class="title has-text-dark">
                      43000000<span class="subtitle has-text-dark">&nbsp(ms)</span>
                  </p>
                  <p style="font-size: 20px;">
                <b>db_duration</b>
                </p>
                </article>
              </div>
            </div>
            <div class="column">
              <div class="tile is-primary  ">
                    <article class="tile is-child p-4 box has-background-white" >
                        <p class="title has-text-dark">
                      43000000<span class="subtitle has-text-dark">&nbsp(ms)</span>
                  </p>
                  <p style="font-size: 20px;">
                <b>db_duration</b>
                </p>
                </article>
              </div>
            </div>
            <div class="column">
              <div class="tile is-primary  ">
                    <article class="tile is-child p-4 box has-background-white" >
                        <p class="title has-text-dark">
                      43000000<span class="subtitle has-text-dark">&nbsp(ms)</span>
                  </p>
                  <p style="font-size: 20px;">
                <b>db_duration</b>
                </p>
                </article>
              </div>
            </div>
            </div>


      <div class="columns is-mobile" style = "display: flex;  flex-direction: row;  flex-wrap: wrap;">
                      <div class="column is-full-mobile is-half-tablet is-half-desktop">
                           <div id='echartContainer0'class="box" phx-hook='node_charts' style="width: 100%; height: 224px;">
                           <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
                      </div>

                      <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='echartContainer1'class="box" phx-hook='node_charts' style="width: 100%; height: 224px ;">
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"> </canvas></div>
                      </div>

                      <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='echartContainer2' class="box" phx-hook='node_charts' style="width: 100%; height: 224px" >
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px">  </canvas></div>
                      </div>

                    <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='echartContainer3'  class="box" phx-hook='node_charts' style="width: 100%; height: 224px" >
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px">  </canvas>   </div >
                    </div >

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='echartContainer4' class="box" phx-hook='node_charts' style="width: 100%; height: 224px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px">   </canvas> </div>
                  </div>

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='echartContainer5' class="box" phx-hook='node_charts' style="width: 100%; height: 224px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"> </canvas> </div>
                  </div>
           </div >
    """
  end
end
