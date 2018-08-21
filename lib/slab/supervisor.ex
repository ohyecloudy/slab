defmodule Slab.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    pipeline_watcher_config = Application.get_env(:slab, :pipeline_watcher)

    children = [{SlackAdapter, []}]

    children =
      if pipeline_watcher_config do
        children ++ [{Gitlab.PipelineWatcherSupervisor, Map.new(pipeline_watcher_config)}]
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
