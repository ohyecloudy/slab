defmodule SlackAdapter do
  use GenServer

  defmodule State do
    defstruct slack_pid: nil
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, pid} =
      Slack.Bot.start_link(SlackAdapter.Handler, [], Application.get_env(:slack, :token), %{
        name: Slack
      })

    {:ok, %{state | slack_pid: pid}}
  end
end
