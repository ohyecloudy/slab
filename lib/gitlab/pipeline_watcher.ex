defmodule Gitlab.PipelineWatcher do
  use GenServer
  require Logger

  defmodule State do
    defstruct last_pipeline_status: nil,
              target_branch: nil,
              poll_changes_interval_ms: nil,
              notify_stack_channel_name: nil
  end

  def start_link(args) do
    Logger.info("start pipeline watcher. config - #{inspect(args)}")

    GenServer.start_link(__MODULE__, Map.merge(%State{}, Map.new(args)),
      name: String.to_atom("#{Atom.to_string(__MODULE__)}_#{args.target_branch}")
    )
  end

  @impl true
  def init(state) do
    state = poll_changes(state)

    schedule_poll_changes(state.poll_changes_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll_changes, state) do
    state = poll_changes(state)

    schedule_poll_changes(state.poll_changes_interval_ms)
    {:noreply, state}
  end

  defp poll_changes(state) do
    branch = state.target_branch
    channel = state.notify_stack_channel_name
    new_status = Gitlab.pipeline_status(branch)
    changed = pipeline_changed_status(state.last_pipeline_status, new_status)

    Logger.info("poll changes, branch - #{branch}, pipeline status - #{changed}")

    case changed do
      :init ->
        SlackAdapter.send_message_to_slack(
          ":cop: #{branch} 브랜치 pipeline 감시를 시작합니다 :cop:",
          channel
        )

        %{state | last_pipeline_status: new_status}

      :not_changed ->
        state

      _ ->
        SlackAdapter.send_message_to_slack(
          "",
          SlackAdapter.Attachments.from_pipelines(new_status),
          channel
        )

        %{state | last_pipeline_status: new_status}
    end
  end

  defp schedule_poll_changes(interval_ms) do
    Process.send_after(self(), :poll_changes, interval_ms)
  end

  defp pipeline_changed_status(nil, _curr), do: :init

  defp pipeline_changed_status(prev, curr) do
    if prev.failed do
      if curr.failed do
        if prev.failed.pipeline["id"] == curr.failed.pipeline["id"] do
          :not_changed
        else
          :still_failing
        end
      else
        :fixed
      end
    else
      if curr.failed do
        :failed
      else
        if prev.success.pipeline["id"] == curr.success.pipeline["id"] do
          :not_changed
        else
          :success
        end
      end
    end
  end
end
