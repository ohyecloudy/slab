defmodule Slab.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [{SlackAdapter, []}]

    pipeline_watcher_config = Application.get_env(:slab, :pipeline_watcher)

    children =
      if pipeline_watcher_config do
        children ++ [{Gitlab.PipelineWatcher, pipeline_watcher_config}]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Slab.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
