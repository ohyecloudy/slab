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

    mention_me = String.contains?(message.text, Keyword.get(state, :slab).mention_str)

    cond do
      # gitlab issue 풀어주는 건 mention 안해도 동작
      Application.get_env(:slab, :enable_poor_gitlab_issue_purling) && issue_in_message ->
        Logger.info("[purling] issue id - #{issue_in_message}")
        post_gitlab_issue(Gitlab.issue(issue_in_message), message.channel)

      mention_me ->
        Logger.info("message #{inspect(message.text)}")

        command =
          message.text
          |> normalize_test(mention_str: Keyword.get(state, :slab).mention_str)
          |> process_aliases

        cond do
          String.contains?(command, "ping") ->
            send_message("pong", message.channel, slack)

          command == "help" ->
            Slack.Web.Chat.post_message(
              message.channel,
              help(),
              %{
                as_user: false,
                token: Application.get_env(:slack, :token),
                unfurl_links: false
              }
            )

          String.contains?(command, "issues") ->
            {start, length} = :binary.match(command, "issues")

            query =
              command
              |> String.slice((start + length)..-1)
              |> String.trim()

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

            Slack.Web.Chat.post_message(
              message.channel,
              Gitlab.Pagination.help_text(headers, query),
              %{
                as_user: false,
                token: Application.get_env(:slack, :token),
                attachments: attachments
              }
            )

          String.contains?(command, "commits-without-mr") ->
            {start, length} = :binary.match(command, "commits-without-mr")

            input_options =
              command
              |> String.slice((start + length)..-1)
              |> String.trim()

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
                "merge request가 없는 commit을 못 찾았습니다. 명령(#{command})",
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
    custom = %{name: slack.me.name, mention_str: "<@#{slack.me.id}>"}
    Logger.info("Hello - bot name(#{custom.name}), mention_str(#{custom.mention_str})")
    {:ok, put_in(state[:slab], custom)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  defp normalize_test(text, mention_str: mention) do
    # html 특수문자를 변환해주는 함수가 있을법 한데, 못 찾음
    text
    |> String.replace(mention, "")
    |> String.trim()
    |> String.replace("&gt;", ">")
    |> String.replace("&lt;", "<")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
  end

  defp process_aliases(command) do
    ret =
      Application.get_env(:slab, :aliases)
      |> Enum.reduce(command, fn {k, v}, acc ->
        String.replace(acc, Atom.to_string(k), v, global: false)
      end)

    if command != ret do
      Logger.info("process aliases: #{command} -> #{ret}")
    end

    ret
  end

  defp post_gitlab_issue(issue, channel) do
    attachments = SlackAdapter.Attachments.from_issue(issue, :detail)

    if Enum.empty?(attachments) do
      Logger.info("[purling] skip")
    else
      Slack.Web.Chat.post_message(channel, "", %{
        as_user: false,
        token: Application.get_env(:slack, :token),
        attachments: Poison.encode!(attachments)
      })

      Logger.info("[purling] success")
    end
  end

  defp help() do
    """
    `issues` - gitlab issue를 조회합니다. 사용할 수 있는 옵션은 https://docs.gitlab.com/ee/api/issues.html#list-issues 참고
    ```
    @slab issues %{"labels" => "foo,bar", "state" => "opened"}
    ```

    `commits-without-mr` - merge request가 없는 commit을 조회합니다. author 이름을 넣으면 해당 author의 commit만 조회합니다.
    ```
    @slab commits-without-mr --date 2018-06-27
    @slab commits-without-mr user1 user2 --date 2018-06-27
    ```
    """
  end
end
