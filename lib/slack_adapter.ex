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

    # TODO[ohyecloudy] 멘션 스트링 안 바뀜. hello에서 처리해서 저장
    mention_me =
      with slab when not is_nil(slab) <- Keyword.get(state, :slab),
           id <- slab.id do
        mention = "<@#{id}>"
        String.contains?(message.text, mention)
      else
        _ -> false
      end

    cond do
      # gitlab issue 풀어주는 건 mention 안해도 동작
      Application.get_env(:slab, :enable_poor_gitlab_issue_purling) && issue_in_message ->
        Logger.info("[purling] issue id - #{issue_in_message}")
        post_gitlab_issue(Gitlab.issue(issue_in_message), message.channel)

      mention_me ->
        # TODO[ohyecloudy]: 멘션 스트링을 지움, 트림도 같이
        cond do
          String.contains?(message.text, "ping") ->
            send_message("pong", message.channel, slack)

          String.contains?(message.text, "issues") ->
            {start, length} = :binary.match(message.text, "issues")

            # TODO[ohyecloudy] html 특수문자를 변환해주는 함수가 있을법 한데, 못 찾음
            query =
              message.text
              |> String.slice((start + length)..-1)
              |> String.trim()
              |> String.replace("&gt;", ">")
              |> String.replace("&lt;", "<")
              |> String.replace("&nbsp;", " ")
              |> String.replace("&amp;", "&")

            Logger.info("issues input text query - #{query}")

            query =
              query
              |> Code.eval_string()
              |> elem(0)

            Logger.info("issues query - #{inspect(query)}")

            %{headers: headers, body: body} = Gitlab.issues(query)

            attachments =
              body
              |> SlackAdapter.Attachments.from_issues(:summary)
              |> Poison.encode!()

            pagination_info =
              if map_size(headers) > 0 do
                {total, _} = Integer.parse(headers["X-Total-Pages"])
                {cur, _} = Integer.parse(headers["X-Page"])

                prev =
                  if cur > 1 do
                    {_, suggest_option} =
                      Map.get_and_update(query, "page", fn x ->
                        {x, "#{cur - 1}"}
                      end)

                    "`#{inspect(suggest_option)}`, "
                  else
                    ""
                  end

                next =
                  if cur < total do
                    {_, suggest_option} =
                      Map.get_and_update(query, "page", fn x ->
                        {x, "#{cur + 1}"}
                      end)

                    ", `#{inspect(suggest_option)}`"
                  else
                    ""
                  end

                if total > 1 do
                  prev <> "PAGE(#{cur}/#{total})" <> next
                else
                  ""
                end
              else
                ""
              end

            Slack.Web.Chat.post_message(message.channel, pagination_info, %{
              as_user: false,
              token: Application.get_env(:slack, :token),
              attachments: attachments
            })

          String.contains?(message.text, "commits-without-mr") ->
            {start, length} = :binary.match(message.text, "commits-without-mr")

            input_options =
              message.text
              |> String.slice((start + length)..-1)
              |> String.trim()
              |> String.replace("&gt;", ">")
              |> String.replace("&lt;", "<")
              |> String.replace("&nbsp;", " ")
              |> String.replace("&amp;", "&")

            Logger.info("commits-without-mr input options text - #{input_options}")

            {options, target_authors, _} = OptionParser.parse(OptionParser.split(input_options))

            Logger.info(
              "commits-without-mr options - #{inspect(options)}, target authors - #{
                inspect(target_authors)
              }"
            )

            commits =
              with date when not is_nil(date) <- Keyword.get(options, :date),
                   {:ok, from_date} <- Date.from_iso8601(date),
                   to_date <- Date.add(from_date, 1) do
                Logger.info("commits-without-mr #{inspect(from_date)} ~ #{inspect(to_date)}")

                commits_query = %{
                  "since" => Date.to_string(from_date) <> "T00:00:00.000+09:00",
                  "until" => Date.to_string(to_date) <> "T00:00:00.000+09:00"
                }

                Gitlab.Pagination.all(commits_query, &Gitlab.commits/1)
                |> List.flatten()
              else
                _ -> []
              end

            Logger.info("commits count - #{Enum.count(commits)}")

            commits_without_mr =
              commits
              |> Enum.filter(fn %{
                                  "id" => id,
                                  "message" => message,
                                  "author_name" => name,
                                  "author_email" => email
                                } ->
                target_author =
                  if Enum.empty?(target_authors) do
                    true
                  else
                    String.contains?(name, target_authors) ||
                      String.contains?(email, target_authors)
                  end

                # merge commit 정보가 따로 없어서 커밋 메시지로 제외
                merge_commit = String.contains?(message, "See merge request")

                if target_author && !merge_commit do
                  %{body: body} = Gitlab.merge_requests(id)
                  Enum.empty?(body)
                else
                  false
                end
              end)

            Logger.info(
              "commits count without merge requests - #{Enum.count(commits_without_mr)}"
            )

            if Enum.empty?(commits_without_mr) do
              send_message(
                "merge request가 없는 commit을 못 찾았습니다. 옵션(#{input_options})",
                message.channel,
                slack
              )
            else
              commits_without_mr
              |> Enum.chunk_every(SlackAdapter.Attachments.limit_count())
              |> Enum.each(fn commits ->
                attachments =
                  commits
                  |> SlackAdapter.Attachments.from_commits(:summary)
                  |> Poison.encode!()

                Slack.Web.Chat.post_message(message.channel, "", %{
                  as_user: false,
                  token: Application.get_env(:slack, :token),
                  attachments: attachments
                })
              end)
            end

          true ->
            nil
        end

      true ->
        nil
    end

    {:ok, state}
  end

  def handle_event(%{type: "hello"}, slack, state) do
    custom = %{name: slack.me.name, id: slack.me.id}
    Logger.info("Hello - bot name(#{custom.name}), id(#{custom.id})")
    {:ok, put_in(state[:slab], custom)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp post_gitlab_issue(issue, _channel) when map_size(issue) == 0 do
    Logger.info("[purling] skip")
  end

  defp post_gitlab_issue(issue, channel) do
    # TODO[ohyecloudy]: SlackAdapter.Attachments 모듈로 이동
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
