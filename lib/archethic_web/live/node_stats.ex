defmodule ArchEthicWeb.NodeStats do
  @moduledoc false

  use Phoenix.LiveView
  use Phoenix.HTML

  def render(assigns) do
    ~L"""

              <h1 style="font-size: 40px; color: #fff;"> Nodes Statistics</h1>

              <div class="columns">
                  <div class="column">
                      <div class="tile is-primary">
                            <article class="tile is-child p-4 box has-background-white">
                              <p class="title has-text-dark">
                              <span phx-hook="node_charts" id="archethic_self_repair_duration">0.000</span>
                              <span class="subtitle has-text-dark">&nbsp;(ms)</span></p>
                                <p style="font-size: 20px;"> <b>self_repair_duration</b>   </p>
                            </article>
                      </div>
                  </div>
                    <div class="column">
                      <div class="tile is-primary">
                            <article class="tile is-child p-4 box has-background-white">
                              <p class="title has-text-dark">
                              <span phx-hook="node_charts" id="vm_memory_processes">0.000</span>
                              <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                              <p style="font-size: 20px;"><b>vm_memory_processes</b></p>
                            </article>
                      </div>
                    </div>

                  <div class="column">
                      <div class="tile is-primary">
                            <article class="tile is-child p-4 box has-background-white">
                              <p class="title has-text-dark">
                              <span phx-hook="node_charts" id="vm_memory_ets">0.000</span>
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
                              <span phx-hook="node_charts" id="vm_memory_binary">0.000</span>
                              <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                                <p style="font-size: 20px;">
                                <b>vm_memory_binary</b>  </p>    </article>
                      </div>
                </div>
              </div>

              <div class="columns">
              <div class="column">
                  <div class="tile is-primary">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_memory_system">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                            <p style="font-size: 20px;"> <b>vm_memory_system</b>   </p>
                        </article>
                  </div>
              </div>

              <div class="column">
                  <div class="tile is-primary">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_memory_processes_used ">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                          <p style="font-size: 20px;"><b>vm_memory_processes_used</b></p>
                        </article>
                  </div>
              </div>

              <div class="column">
                  <div class="tile is-primary  ">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_memory_total">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                            <p style="font-size: 20px;">
                            <b>vm_memory_total</b>  </p>    </article>
                  </div>
              </div>
      </div>

      <div class="columns">
              <div class="column">
                  <div class="tile is-primary">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_system_counts_process_count">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                            <p style="font-size: 20px;"> <b>vm_system_counts_process_count</b>   </p>
                        </article>
                  </div>
              </div>

              <div class="column">
                  <div class="tile is-primary">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_memory_atom">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                          <p style="font-size: 20px;"><b>vm_memory_atom</b></p>
                        </article>
                  </div>
              </div>

              <div class="column">
                  <div class="tile is-primary">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_total_run_queue_lengths_cpu">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                          <p style="font-size: 20px;">
                            <b>vm_total_run_queue_lengths_cpu</b>
                              </p>    </article>
                  </div>
              </div>

              <div class="column">
                  <div class="tile is-primary  ">
                        <article class="tile is-child p-4 box has-background-white">
                          <p class="title has-text-dark">
                          <span phx-hook="node_charts" id="vm_total_run_queue_lengths_total">0.000</span>
                          <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                            <p style="font-size: 20px;">
                            <b>vm_total_run_queue_lengths_total</b>  </p>    </article>
                  </div>
              </div>
      </div>


      <div class="columns">
            <div class="column">
                <div class="tile is-primary">
                      <article class="tile is-child p-4 box has-background-white">
                        <p class="title has-text-dark">
                        <span phx-hook="node_charts" id="vm_memory_atom_used">0.000</span>
                        <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                          <p style="font-size: 20px;"> <b>vm_memory_atom_used</b>   </p>
                      </article>
                </div>
            </div>

            <div class="column">
                <div class="tile is-primary">
                      <article class="tile is-child p-4 box has-background-white">
                        <p class="title has-text-dark">
                        <span phx-hook="node_charts" id="vm_total_run_queue_lengths_io">0.000</span>
                        <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                        <p style="font-size: 20px;"><b>vm_total_run_queue_lengths_io</b></p>
                      </article>
                </div>
            </div>

            <div class="column">
                <div class="tile is-primary">
                      <article class="tile is-child p-4 box has-background-white">
                        <p class="title has-text-dark">
                        <span phx-hook="node_charts" id="vm_system_counts_port_count">0.000</span>
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
                        <span phx-hook="node_charts" id="vm_memory_code">0.000</span>
                        <span class="subtitle has-text-dark">&nbsp;(kb)</span></p>
                          <p style="font-size: 20px;">
                          <b>vm_memory_code</b>  </p>    </article>
                </div>
             </div>

                  <div class="column">
                <div class="tile is-primary  ">
                      <article class="tile is-child p-4 box has-background-white">
                        <p class="title has-text-dark">
                        <span phx-hook="node_charts" id="vm_system_counts_atom_count">0.000</span>
                        <span class="subtitle has-text-dark">&nbsp;(count)</span></p>
                          <p style="font-size: 20px;">
                          <b>vm_system_counts_atom</b>  </p>    </article>
                </div>
      </div>
     </div>


      <div class="columns is-mobile" style = "display: flex;  flex-direction: row;  flex-wrap: wrap;">
                      <div class="column is-full-mobile is-half-tablet is-half-desktop">
                           <div id='archethic_election_validation_nodes_duration'class="box" phx-hook='node_charts' style="width: 100%; height: 300px;">
                           <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"></canvas></div>
                      </div>

                      <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='archethic_election_storage_nodes_duration'class="box" phx-hook='node_charts' style="width: 100%; height: 300px ;">
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"> </canvas></div>
                      </div>

                      <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='archethic_mining_pending_transaction_validation_duration' class="box" phx-hook='node_charts' style="width: 100%; height: 300px" >
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px">  </canvas></div>
                      </div>

                    <div class="column is-full-mobile is-half-tablet is-half-desktop">
                        <div id='archethic_mining_proof_of_work_duration'  class="box" phx-hook='node_charts' style="width: 100%; height: 300px" >
                        <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px">  </canvas>   </div >
                    </div >

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='archethic_mining_full_transaction_validation_duration' class="box" phx-hook='node_charts' style="width: 100%; height: 300px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px">   </canvas> </div>
                  </div>

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='archethic_contract_parsing_duration' class="box" phx-hook='node_charts' style="width: 100%; height: 300px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"> </canvas> </div>
                  </div>

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='archethic_mining_fetch_context_duration' class="box" phx-hook='node_charts' style="width: 100%; height: 300px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"> </canvas> </div>
                  </div>

                  <div class="column is-full-mobile is-half-tablet is-half-desktop">
                      <div id='archethic_db_duration' class="box" phx-hook='node_charts' style="width: 100%; height: 300px" >
                      <canvas id="echartDiv"  phx-update='ignore' style="width: 100%; min-height: 200px"> </canvas> </div>
                  </div>
           </div >
    """
  end



    # buffer task async stream
    def mount(_params, _session, socket) do
      if connected?(socket) do
        ArchEthic.Metrics.MetricClient.monitor()
        :timer.send_interval(1_250, self(), :update)
      end

      {:ok, socket}
    end

    def handle_info(:update, socket) do
      new_points = ArchEthic.Metrics.MetricClient.get_this_node_points()
      {:noreply, socket |> push_event("node_points", %{points: new_points})}
    end

end
