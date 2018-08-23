defmodule Slab.Server do
  use GenServer

  defmodule State do
    defstruct sup: nil, pipeline_watcher_sup: nil
  end

  def start_link(%{sup: pid}) do
    GenServer.start_link(__MODULE__, %State{sup: pid}, name: __MODULE__)
  end

  def start_pipeline_watcher() do
    GenServer.cast(__MODULE__, :start_pipeline_watcher)
  end

  def stop_pipeline_watcher() do
    GenServer.cast(__MODULE__, :stop_pipeline_watcher)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast(:start_pipeline_watcher, state) do
    pipeline_watcher_config = Application.get_env(:slab, :pipeline_watcher)

    state =
      if pipeline_watcher_config && state.pipeline_watcher_sup == nil do
        spec = {Gitlab.PipelineWatcherSupervisor, Map.new(pipeline_watcher_config)}
        {:ok, pid} = Supervisor.start_child(state.sup, spec)

        %{state | pipeline_watcher_sup: pid}
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:stop_pipeline_watcher, state) do
    state =
      if state.pipeline_watcher_sup do
        :ok = Supervisor.terminate_child(state.sup, Gitlab.PipelineWatcherSupervisor)
        :ok = Supervisor.delete_child(state.sup, Gitlab.PipelineWatcherSupervisor)
        %{state | pipeline_watcher_sup: nil}
      else
        state
      end

    {:noreply, state}
  end
end
