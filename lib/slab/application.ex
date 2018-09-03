defmodule Slab.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    Slab.Supervisor.start_link(args)
  end
end
