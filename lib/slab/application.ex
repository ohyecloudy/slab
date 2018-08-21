defmodule Slab.Application do
  @moduledoc false

  use Application

  def start(_type, args) do
    Slab.Supervisor.start_link(args)
  end
end
