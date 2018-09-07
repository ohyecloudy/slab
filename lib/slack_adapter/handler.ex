defmodule SlackAdapter.Handler do
  require Logger
  use Slack
  use HTTPoison.Base

  def handle_event(message = %{type: "message", text: text, user: user}, slack, state) do
    issue_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/issues"

    issue_in_message =
      with {:ok, re} <- Regex.compile(Regex.escape(issue_base_url) <> "/(?<issue>\\d+)"),
           ret when not is_nil(ret) <- Regex.named_captures(re, text),
           {num, ""} <- Integer.parse(ret["issue"]) do
        num
      else
        _ -> nil
      end

    mention_me = String.contains?(text, Keyword.get(state, :slab).mention_str)

    # @user_name에서 @ 문자를 제거
    user_name = String.slice(Slack.Lookups.lookup_user_name(user, slack), 1..-1)

    master = Enum.any?(Application.get_env(:slab, :masters), fn name -> user_name == name end)

    cond do
      # gitlab issue 풀어주는 건 mention 안해도 동작
      Application.get_env(:slab, :enable_poor_gitlab_issue_purling) && issue_in_message ->
        Logger.info("[purling] issue id - #{issue_in_message}")
        post_gitlab_issue(Gitlab.issue(issue_in_message), message.channel)

      mention_me ->
        Logger.info(
          "message - #{inspect(text)}, user_name - #{user_name}, master - #{inspect(master)}"
        )

        command =
          text
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
            command
            |> extract_options("issues")
            |> process_issues(message.channel)

          String.contains?(command, "commits-without-mr") ->
            command
            |> extract_options("commits-without-mr")
            |> process_commits_without_mr(slack, message.channel)

          String.contains?(command, "self-merge") ->
            command
            |> extract_options("self-merge")
            |> process_self_merge(slack, message.channel)

          String.contains?(command, "branch-access") && master ->
            command
            |> extract_options("branch-access")
            |> process_branch_access(message.channel)

          String.contains?(command, "pipelines") ->
            command
            |> extract_options("pipelines")
            |> process_pipelines(message.channel)

          String.contains?(command, "pipeline-watcher") ->
            command
            |> extract_options("pipeline-watcher")
            |> process_pipeline_watcher(slack, message.channel)

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
    Logger.info("local time zone - #{inspect(Timex.Timezone.local())}")
    Slab.Server.start_pipeline_watcher()
    {:ok, put_in(state[:slab], custom)}
  end

  def handle_event(_, _, state), do: {:ok, state}

  def handle_info({:message, text, attachments, channel}, _slack, state) do
    Slack.Web.Chat.post_message(channel, text, %{
      as_user: false,
      token: Application.get_env(:slack, :token),
      attachments: Poison.encode!(attachments)
    })

    {:ok, state}
  end

  @spec normalize_test(String.t(), keyword(String.t())) :: String.t()
  defp normalize_test(text, mention_str: mention) do
    # html 특수문자를 변환해주는 함수가 있을법 한데, 못 찾음
    text
    |> String.replace(mention, "")
    |> String.trim()
    |> String.replace("&gt;", ">")
    |> String.replace("&lt;", "<")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("”", "\"")
    |> String.replace("“", "\"")
  end

  @spec process_aliases(String.t()) :: String.t()
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

  @spec post_gitlab_issue(map(), String.t()) :: :ok
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

  @spec help() :: String.t()
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

    `self-merge` - merge request를 만든 사람과 머지한 사람이 같은 merge request를 출력합니다. author 이름을 넣으면 해당 author의 merge request만 검사합니다.
    ```
    @slab self-merge --date 2018-06-27
    @slab self-merge user1 user2 --date 2018-06-27
    ```

    `branch-access` - protected branches 접근 레벨을 변경합니다. 레벨 값으로 no, developer, maintainer, admin 문자를 사용할 수 있습니다.
    :admission_tickets: *master* 권한을 가진 유저만 실행할 수 있는 명령어 입니다.
    ```
    @slab branch-access --branch master --level no
    ```

    `pipelines` - pipeline 상태를 조회합니다.
    ```
    @slab pipelines --branch master
    ```

    `pipeline-watcher start/stop` - pipeline 상태 감시를 시작하거나 중지합니다.
    ```
    @slab pipeline-watcher stop
    ```
    """
  end

  @spec extract_options(String.t(), String.t()) :: String.t()
  defp extract_options(full, command) do
    {start, length} = :binary.match(full, command)

    full
    |> String.slice((start + length)..-1)
    |> String.trim()
  end

  @spec process_issues(String.t(), String.t()) :: any()
  defp process_issues(options, channel) do
    Logger.info("issue options before eval - #{options}")

    options =
      options
      |> Code.eval_string()
      |> elem(0)

    Logger.info("issue options after eval - #{inspect(options)}")

    %{headers: headers, body: body} = Gitlab.issues(options)

    attachments =
      body
      |> SlackAdapter.Attachments.from_issues(:summary)
      |> Poison.encode!()

    Slack.Web.Chat.post_message(
      channel,
      Gitlab.Pagination.help_text(headers, options),
      %{
        as_user: false,
        token: Application.get_env(:slack, :token),
        attachments: attachments
      }
    )
  end

  @spec process_commits_without_mr(String.t(), map(), String.t()) :: any()
  defp process_commits_without_mr(options, slack, channel) do
    Logger.info("commits-without-mr input options text - #{options}")

    {options, target_authors, _} =
      OptionParser.parse(OptionParser.split(options), switches: [date: :string])

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

        Gitlab.PaginationStream.create(&Gitlab.commits/1, commits_query)
        |> Enum.to_list()
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
            String.contains?(name, target_authors) || String.contains?(email, target_authors)
          end

        # merge commit 정보가 따로 없어서 커밋 메시지로 제외
        merge_commit = String.contains?(message, "See merge request")

        if target_author && !merge_commit do
          %{body: body} = Gitlab.merge_requests_associated_with(id)
          Enum.empty?(body)
        else
          false
        end
      end)

    Logger.info("commits count without merge requests - #{Enum.count(commits_without_mr)}")

    if Enum.empty?(commits_without_mr) do
      send_message(
        "merge request가 없는 commit을 못 찾았습니다.",
        channel,
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

        Slack.Web.Chat.post_message(
          channel,
          "merge request가 없는 commit을 총 #{Enum.count(commits_without_mr)}개 찾았습니다.",
          %{
            as_user: false,
            token: Application.get_env(:slack, :token),
            attachments: attachments
          }
        )
      end)
    end
  end

  @spec process_self_merge(String.t(), map(), String.t()) :: any()
  defp process_self_merge(options, slack, channel) do
    Logger.info("self-merge input options text - #{options}")

    {options, target_authors, _} =
      OptionParser.parse(OptionParser.split(options), switches: [date: :string])

    Logger.info(
      "self-merge options - #{inspect(options)}, target authors - #{inspect(target_authors)}"
    )

    merge_requests =
      with date when not is_nil(date) <- Keyword.get(options, :date),
           {:ok, from_date} <- Date.from_iso8601(date),
           to_date <- Date.add(from_date, 1) do
        Logger.info("self-merge #{inspect(from_date)} ~ #{inspect(to_date)}")

        mr_query = %{
          "updated_after" => Date.to_string(from_date) <> "T00:00:00.000+09:00",
          "updated_before" => Date.to_string(to_date) <> "T00:00:00.000+09:00",
          "state" => "merged"
        }

        Gitlab.PaginationStream.create(&Gitlab.merge_requests/1, mr_query)
        |> Enum.to_list()
      else
        _ -> []
      end

    Logger.info("merge request count - #{Enum.count(merge_requests)}")

    merge_requests =
      if Enum.empty?(target_authors) do
        merge_requests
      else
        merge_requests
        |> Enum.filter(fn %{"author" => author} ->
          if author do
            String.contains?(author["username"], target_authors) ||
              String.contains?(author["name"], target_authors)
          else
            false
          end
        end)
      end

    Logger.info(
      "filtered merge request count - #{Enum.count(merge_requests)}, target authors - #{
        inspect(target_authors)
      }"
    )

    merge_requests =
      merge_requests
      |> Enum.map(fn %{"iid" => id} -> Gitlab.merge_request(id) end)
      |> Enum.filter(fn %{"author" => author, "merged_by" => merged_by} ->
        if author && merged_by do
          author["id"] == merged_by["id"]
        else
          false
        end
      end)

    if Enum.empty?(merge_requests) do
      send_message(
        "self merge한 merge request를 못 찾았습니다.",
        channel,
        slack
      )
    else
      merge_requests
      |> Enum.chunk_every(SlackAdapter.Attachments.limit_count())
      |> Enum.each(fn mrs ->
        attachments =
          mrs
          |> SlackAdapter.Attachments.from_merge_requests()
          |> Poison.encode!()

        Slack.Web.Chat.post_message(
          channel,
          "self merge한 merge request를 총 #{Enum.count(merge_requests)}개 찾았습니다.",
          %{
            as_user: false,
            token: Application.get_env(:slack, :token),
            attachments: attachments
          }
        )
      end)
    end
  end

  @spec process_branch_access(String.t(), String.t()) :: any()
  def process_branch_access(options, channel) do
    Logger.info("branch-access input options text - #{options}")

    {options, _, _} =
      OptionParser.parse(OptionParser.split(options), switches: [branch: :string, level: :string])

    Logger.info("branch-access options - #{inspect(options)}")

    with branch when not is_nil(branch) <- Keyword.get(options, :branch),
         level when not is_nil(level) <-
           Gitlab.protected_branches_access_level(Keyword.get(options, :level)) do
      %{body: body} =
        Gitlab.protected_branches(%{
          name: branch,
          push_access_level: "#{level}",
          merge_access_level: "#{level}"
        })

      Logger.info("branch-access response - #{inspect(body)}")

      attachments =
        body
        |> SlackAdapter.Attachments.from_protected_branches()
        |> Poison.encode!()

      Slack.Web.Chat.post_message(channel, "", %{
        as_user: false,
        token: Application.get_env(:slack, :token),
        attachments: attachments
      })
    end
  end

  @spec process_pipelines(String.t(), String.t()) :: any()
  def process_pipelines(options, channel) do
    {options, _, _} = OptionParser.parse(OptionParser.split(options), switches: [branch: :string])

    Logger.info("pipelines options - #{inspect(options)}")

    with branch when not is_nil(branch) <- Keyword.get(options, :branch) do
      attachments =
        Gitlab.pipeline_status(branch)
        |> SlackAdapter.Attachments.from_pipelines()
        |> Poison.encode!()

      Slack.Web.Chat.post_message(channel, "", %{
        as_user: false,
        token: Application.get_env(:slack, :token),
        attachments: attachments
      })
    end
  end

  @spec process_pipeline_watcher(String.t(), map(), String.t()) :: any()
  def process_pipeline_watcher(options, slack, channel) do
    options =
      case options do
        "start" -> {:ok, true}
        "stop" -> {:ok, false}
        _ -> {:error, options}
      end

    Logger.info("pipeline-watcher options - #{inspect(options)}")

    with {:ok, is_start} <- options do
      if is_start do
        Slab.Server.start_pipeline_watcher()
        send_message(":mag: 파이프라인 감시를 시작합니다 :mag:", channel, slack)
      else
        Slab.Server.stop_pipeline_watcher()
        send_message(":mag: 파이프라인 감시를 중지합니다 :mag:", channel, slack)
      end
    end
  end
end
