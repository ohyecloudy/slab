defmodule SlackAdapter do
  use GenServer

  defmodule State do
    defstruct slack_pid: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def send_message_to_slack(text, attachments \\ [], channel) do
    GenServer.cast(__MODULE__, {:message_to_slack, text, attachments, channel})
  end

  @impl true
  def init(state) do
    {:ok, pid} =
      Slack.Bot.start_link(SlackAdapter.Handler, [], Application.get_env(:slack, :token), %{
        name: Slack
      })

    {:ok, %{state | slack_pid: pid}}
  end

  @impl true
  def handle_cast({:message_to_slack, text, attachments, channel}, state) do
    send(state.slack_pid, {:message, text, attachments, channel})
    {:noreply, state}
  end
end
