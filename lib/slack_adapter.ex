defmodule SlackAdapter do
  require Logger
  use Slack
  use HTTPoison.Base

  def start_link(args) do
    Slack.Bot.start_link(SlackAdapter, args, Application.get_env(:slack, :token))
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def handle_event(message = %{type: "message"}, slack, state) do
    issue_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/issues"

    issue_in_message =
      with {:ok, re} <- Regex.compile(Regex.escape(issue_base_url) <> "/(?<issue>\\d+)"),
           ret when not is_nil(ret) <- Regex.named_captures(re, message.text),
           {num, ""} <- Integer.parse(ret["issue"]) do
        num
      else
        _ -> nil
      end

    cond do
      Application.get_env(:slab, :enable_poor_gitlab_issue_purling) && issue_in_message ->
        Logger.info("[purling] issue id - #{issue_in_message}")
        post_gitlab_issue(Gitlab.issue(issue_in_message), message.channel)

      message.text == "ping" ->
        send_message("pong", message.channel, slack)

      true ->
        nil
    end

    {:ok, state}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp post_gitlab_issue(issue, _channel) when map_size(issue) == 0 do
    Logger.info("[purling] skip")
  end

  defp post_gitlab_issue(issue, channel) do
    author =
      if issue["assignee"] == nil do
        %{author_name: "담당자 없음"}
      else
        %{
          author_name: issue["assignee"]["name"],
          author_icon: issue["assignee"]["avatar_url"],
          author_link: issue["assignee"]["web_url"]
        }
      end

    attachments =
      [
        Map.merge(
          %{
            fallback: "#{issue["title"]}",
            color: "#939393",
            title: "\##{issue["iid"]} #{issue["title"]}",
            title_link: "#{issue["web_url"]}",
            text: "#{String.slice(issue["description"], 0..100)}",
            fields: [
              %{
                title: "labels",
                value: Enum.join(issue["labels"], ","),
                short: false
              }
            ],
            footer: "slab"
          },
          author
        )
      ]
      |> Poison.encode!()

    Slack.Web.Chat.post_message(channel, "", %{
      as_user: false,
      token: Application.get_env(:slack, :token),
      attachments: [attachments]
    })

    Logger.info("[purling] success")
  end
end
