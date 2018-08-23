defmodule Slab.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [{SlackAdapter, []}, {Slab.Server, %{sup: self()}}]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
