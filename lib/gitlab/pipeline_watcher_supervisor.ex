defmodule Gitlab.PipelineWatcherSupervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(%{target_branch_list: target_branch_list} = args) do
    args = Map.delete(args, :target_branch_list)

    children =
      target_branch_list
      |> Enum.map(fn branch_name ->
        Supervisor.child_spec(
          {Gitlab.PipelineWatcher, Map.put(args, :target_branch, branch_name)},
          id: String.to_atom(branch_name)
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
