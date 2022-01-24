defmodule ArchEthicWeb.NetworkMetricsLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """

  use Phoenix.LiveView
  use Phoenix.HTML

  def mount(_params, _session, socket) do
    if connected?(socket) do
      ArchEthic.Metrics.MetricClient.monitor()
      :timer.send_interval(1_250, self(), :update)
    end

    {:ok, socket}
  end

  def handle_info(:update, socket) do
    data = ArchEthic.Metrics.MetricClient.subscribe_to_network_updates()
    {:noreply, socket |> push_event("network_points", %{points: data})}
  end

  def render(assigns) do
    ~L"""
            <h2 style="font-size: 40px; color: #fff;">Network Telemetry</h2>

              <div class="columns">
                      <div class="column">
                          <div class="tile is-primary">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="archethic_self_repair_duration">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(ms)</span></p>
                                    <p style="font-size: 20px;"> <b>self_repair_duration</b>   </p>
                                </article>
                          </div>
                      </div>

                      <div class="column">
                          <div class="tile is-primary">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="vm_memory_processes">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                  <p style="font-size: 20px;"><b>vm_memory_processes</b></p>
                                </article>
                          </div>
                      </div>

                      <div class="column">
                          <div class="tile is-primary">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="vm_memory_ets">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                  <p style="font-size: 20px;">
                                    <b>vm_memory_ets</b>
                                      </p>    </article>
                          </div>
                      </div>

                      <div class="column">
                          <div class="tile is-primary  ">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="vm_memory_binary">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                    <p style="font-size: 20px;">
                                    <b>vm_memory_binary</b>  </p>    </article>
                          </div>
                      </div>
              </div>

            <div class="columns is-mobile" style = "display:flex;flex-direction:row;flex-wrap:wrap;">
                    <div class="column is-full-mobile is-half-tablet is-half-desktop">
                    <div id='archethic_db_duration' class="box" phx-hook='network_charts' style="width: 100%; height: 300px" >
                    <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px"> </canvas> </div>
                </div>

                <div class="column is-full-mobile is-half-tablet is-half-desktop">
                  <div id='archethic_mining_full_transaction_validation_duration' class="box" phx-hook='network_charts' style="width: 100%; height: 300px" >
                  <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px"> </canvas> </div>
           </div>


              <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='archethic_election_validation_nodes_duration'class="box" phx-hook='network_charts' style="width: 100%; height: 300px;">
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px"></canvas></div>
                </div>
                <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='archethic_election_storage_nodes_duration'class="box" phx-hook='network_charts' style="width: 100%; height: 300px ;">
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px"> </canvas></div>
                      </div>
                </div>


              <div class="columns">
                      <div class="column">
                          <div class="tile is-primary">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="vm_memory_system">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                    <p style="font-size: 20px;"> <b>vm_memory_system</b>   </p>
                                </article>
                          </div>
                      </div>

                      <div class="column">
                          <div class="tile is-primary">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="vm_memory_processes_used">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                  <p style="font-size: 20px;"><b>vm_memory_processes_used</b></p>
                                </article>
                          </div>
                      </div>



                      <div class="column">
                          <div class="tile is-primary  ">
                                <article class="tile is-child p-4 box has-background-white">
                                  <p class="title has-text-dark">
                                  <span phx-hook="network_charts" id="vm_memory_total">0.000</span>
                                  <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                    <p style="font-size: 20px;">
                                    <b>vm_memory_total</b>  </p>    </article>
                          </div>
                      </div>
              </div>





       <div class="tile is-ancestor">
                      <div class="tile is-7 is-parent">
                            <article class="tile is-child box">
                               <div id='archethic_p2p_send_message_duration'
                                phx-hook='network_charts' style="width: 100%; height: 448px" > <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 448px">  </canvas></div>
                                </article>
                      </div>

                      <div class="tile is-5 is-vertical">
                              <div class= "tile">

                                          <div class="tile is-parent">
                                          <article class="tile is-child p-4 box has-background-white">
                                          <p class="title has-text-dark">
                                          <span phx-hook="network_charts" id="vm_system_counts_process_count">0.000</span>
                                          <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                                            <p style="font-size: 20px;"> <b>vm_system_counts_process</b>   </p>
                                        </article>
                                          </div>
                                          <div class="tile is-parent">
                                          <article class="tile is-child p-4 box has-background-white">
                                          <p class="title has-text-dark">
                                          <span phx-hook="network_charts" id="vm_memory_atom">0.000</span>
                                          <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                          <p style="font-size: 20px;"><b>vm_memory_atom</b></p>
                                        </article>
                                          </div>

                                </div>


                              <div class= "tile is-parent">
                                  <article class="tile is-child">
                                  <div id='archethic_mining_pending_transaction_validation_duration' class="box" phx-hook='network_charts' style="width: 100%; height: 250px" >
                                  <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 250px">  </canvas></div>
                                </div>
                                  </article>
                              </div>
                    </div>
                 </div>

        <div class="tile  is-ancestor">
              <div class="tile is-6 is-parent">
                  <article class="tile is-child">
                  <div id='archethic_mining_fetch_context_duration' class="box" phx-hook='network_charts' style="width: 100%; height: 270px" >
                  <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 270px"> </canvas> </div>
                  </article>
              </div>
              <div class="tile  is-vertical">
              <div class="tile  is-parent"> <article class="tile is-child p-4 box has-background-white">
              <p class="title has-text-dark">
              <span phx-hook="network_charts" id="vm_total_run_queue_lengths_cpu">0.000</span>
              <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
              <p style="font-size: 20px;">
                <b>vm_total_run_queue_lengths_cpu</b>
                  </p>    </article></div>
              <div class="tile  is-parent">
              <article class="tile is-child p-4 box has-background-white">
              <p class="title has-text-dark">
              <span phx-hook="network_charts" id="vm_total_run_queue_lengths_total">0.000</span>
              <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                <p style="font-size: 20px;">
                <b>vm_total_run_queue_lengths_total</b>  </p>    </article>
              </div>
              </div>
        </div>
          <div class="columns">
                  <div class="column">
                      <div class="tile is-primary">

                      </div>
                  </div>

                  <div class="column">
                      <div class="tile is-primary  ">

                      </div>
                  </div>
          </div>

          <div class="columns">
                <div class="column">
                    <div class="tile is-primary">
                          <article class="tile is-child p-4 box has-background-white">
                            <p class="title has-text-dark">
                            <span phx-hook="network_charts" id="vm_memory_atom_used">0.000</span>
                            <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                              <p style="font-size: 20px;"> <b>vm_memory_atom_used</b>   </p>
                          </article>
                    </div>
                </div>

                <div class="column">
                    <div class="tile is-primary">
                          <article class="tile is-child p-4 box has-background-white">
                            <p class="title has-text-dark">
                            <span phx-hook="network_charts" id="vm_total_run_queue_lengths_io">0.000</span>
                            <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                            <p style="font-size: 20px;"><b>vm_total_run_queue_lengths_io</b></p>
                          </article>
                    </div>
                </div>

                <div class="column">
                    <div class="tile is-primary">
                          <article class="tile is-child p-4 box has-background-white">
                            <p class="title has-text-dark">
                            <span phx-hook="network_charts" id="vm_system_counts_port_count">0.000</span>
                            <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                            <p style="font-size: 20px;">
                              <b>vm_system_counts_port</b>
                                </p>    </article>
                    </div>
                </div>

                <div class="column">
                    <div class="tile is-primary  ">
                          <article class="tile is-child p-4 box has-background-white">
                            <p class="title has-text-dark">
                            <span phx-hook="network_charts" id="vm_memory_code">0.000</span>
                            <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                              <p style="font-size: 20px;">
                              <b>vm_memory_code</b>  </p>    </article>
                    </div>
                 </div>

                      <div class="column">
                    <div class="tile is-primary  ">
                          <article class="tile is-child p-4 box has-background-white">
                            <p class="title has-text-dark">
                            <span phx-hook="network_charts" id="vm_system_counts_atom_count">0.000</span>
                            <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                              <p style="font-size: 20px;">
                              <b>vm_system_counts_atom</b>  </p>    </article>
                    </div>
                </div>
         </div>

          <div class="columns is-mobile" style = "display:flex;flex-direction:row;flex-wrap:wrap;">

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                    <div id='archethic_mining_proof_of_work_duration'  class="box" phx-hook='network_charts' style="width: 100%; height: 300px" >
                    <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px">  </canvas>   </div >
                  </div >

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='archethic_contract_parsing_duration' class="box" phx-hook='network_charts' style="width: 100%; height: 300px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 300px"> </canvas> </div>
                  </div>

              </div>

    """
  end
end
