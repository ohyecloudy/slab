defmodule SlackAdapter.Handler do
  require Logger
  use Slack
  use HTTPoison.Base

  def handle_event(
        %{type: "message", text: text, user: user, channel: channel},
        slack,
        state
      ) do
    handle_message(text, user, channel, slack, state)
  end

  def handle_event(
        %{type: "message", bot_id: bot, channel: channel, attachments: attachments},
        slack,
        state
      ) do
    state =
      attachments
      |> Enum.reduce(state, fn x, state ->
        text = Map.get(x, :pretext, nil)
        {:ok, state} = handle_message(text, bot, channel, slack, state)
        state
      end)

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

  defp handle_message(nil, _user, _channel, _slack, state), do: {:ok, state}

  defp handle_message(text, user, channel, slack, state) do
    issue_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/issues"
    mr_base_url = Keyword.get(Application.get_env(:slab, :gitlab), :url) <> "/merge_requests"

    issue_in_message =
      with {:ok, re} <- Regex.compile(Regex.escape(issue_base_url) <> "/(?<issue>\\d+)"),
           ret when not is_nil(ret) <- Regex.named_captures(re, text),
           {num, ""} <- Integer.parse(ret["issue"]) do
        num
      else
        _ -> nil
      end

    mr_in_message =
      with {:ok, re} <- Regex.compile(Regex.escape(mr_base_url) <> "/(?<mr>\\d+)"),
           ret when not is_nil(ret) <- Regex.named_captures(re, text),
           {num, ""} <- Integer.parse(ret["mr"]) do
        num
      else
        _ -> nil
      end

    mention_me = String.contains?(text, Keyword.get(state, :slab).mention_str)

    # @user_name에서 @ 문자를 제거
    user_name = String.slice(Slack.Lookups.lookup_user_name(user, slack), 1..-1)

    master_list = Application.get_env(:slab, :masters)
    master = master_list == nil or Enum.any?(master_list, fn name -> user_name == name end)

    cond do
      # gitlab issue 풀어주는 건 mention 안해도 동작
      Application.get_env(:slab, :enable_poor_gitlab_issue_purling) && issue_in_message ->
        Logger.info("[purling] issue id - #{issue_in_message}")
        post_gitlab_issue(Gitlab.issue(issue_in_message), channel)

      # merge request 풀어주는 건 mention 안해도 동작
      Application.get_env(:slab, :enable_poor_gitlab_mr_purling) && mr_in_message ->
        Logger.info("[purling] mr id - #{mr_in_message}")

        post_gitlab_merge_request_with_issues(
          Gitlab.merge_request_with_related_issues(mr_in_message),
          channel
        )

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
            send_message("pong", channel, slack)

          command == "help" ->
            Slack.Web.Chat.post_message(
              channel,
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
            |> process_issues(channel)

          String.contains?(command, "commits-without-mr") ->
            command
            |> extract_options("commits-without-mr")
            |> process_commits_without_mr(slack, channel)

          String.contains?(command, "self-merge") ->
            command
            |> extract_options("self-merge")
            |> process_self_merge(slack, channel)

          String.contains?(command, "branch-access") && master ->
            command
            |> extract_options("branch-access")
            |> process_branch_access(channel)

          String.contains?(command, "pipelines") ->
            command
            |> extract_options("pipelines")
            |> process_pipelines(channel)

          String.contains?(command, "pipeline-watcher") ->
            command
            |> extract_options("pipeline-watcher")
            |> process_pipeline_watcher(slack, channel)

          String.contains?(command, "due-date") ->
            command
            |> extract_options("due-date")
            |> process_due_date(slack, channel)

          true ->
            nil
        end

      true ->
        nil
    end

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

  @spec post_gitlab_merge_request_with_issues(map(), String.t()) :: :ok
  defp post_gitlab_merge_request_with_issues(mr_with_issues, channel) do
    attachments = SlackAdapter.Attachments.from_merge_request_with_issues(mr_with_issues)

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
    https://github.com/ohyecloudy/slab/blob/master/README.org
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
           {:ok, from_date} <- parse_date(date),
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
           {:ok, from_date} <- parse_date(date),
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

  @spec process_due_date(String.t(), map(), String.t()) :: any()
  def process_due_date("", _slack, channel) do
    Application.get_env(:slab, :gitlab_slack_ids)
    |> Enum.each(fn {gitlab_id, _} ->
      Logger.info("due_date options - #{inspect(gitlab_id)}")

      due_date_attachments(gitlab_id, active_started_milestone_ids())
      |> message_due_dates(channel, gitlab_id)
    end)
  end

  def process_due_date(options, _slack, channel) do
    Logger.info("due_date options - #{inspect(options)}")

    gitlab_id = options

    due_date_attachments(gitlab_id, active_started_milestone_ids())
    |> message_due_dates(channel, gitlab_id)
  end

  @spec active_started_milestone_ids() :: [integer()]
  defp active_started_milestone_ids() do
    today = Date.utc_today()

    Gitlab.milestones(%{state: "active"})
    |> Enum.filter(fn %{"start_date" => date} ->
      case Date.from_iso8601(date || "") do
        {:ok, date} -> Date.compare(today, date) in [:gt, :eq]
        _ -> false
      end
    end)
    |> Enum.map(fn %{"id" => id} -> id end)
  end

  defp message_due_dates(%{gt: [], eq: [], lt: [], need_due_dates: []}, channel, gitlab_id) do
    Slack.Web.Chat.post_message(
      channel,
      "#{gitlab_id} :mailbox_with_no_mail:",
      %{
        as_user: false,
        token: Application.get_env(:slack, :token)
      }
    )
  end

  defp message_due_dates(
         %{gt: gt, eq: eq, lt: lt, need_due_dates: need_due_dates},
         channel,
         gitlab_id
       ) do
    Slack.Web.Chat.post_message(
      channel,
      "#{mention_string_from_gitlab_id(gitlab_id)} :mailbox_with_mail::bird:",
      %{
        as_user: false,
        token: Application.get_env(:slack, :token)
      }
    )

    if not Enum.empty?(gt) do
      Slack.Web.Chat.post_message(
        channel,
        ":rotating_light::fallen_leaf: due date가 지났습니다. 재설정 해주세요.",
        %{
          as_user: false,
          token: Application.get_env(:slack, :token),
          attachments: Poison.encode!(gt)
        }
      )
    end

    if not Enum.empty?(need_due_dates) do
      Slack.Web.Chat.post_message(
        channel,
        ":rotating_light::calendar: due date를 설정 안 한 이슈 목록입니다. due date를 설정하세요.",
        %{
          as_user: false,
          token: Application.get_env(:slack, :token),
          attachments: Poison.encode!(need_due_dates)
        }
      )
    end

    if not Enum.empty?(eq) do
      Slack.Web.Chat.post_message(
        channel,
        ":star-struck:::muscle: 오늘 마감 목록입니다.",
        %{
          as_user: false,
          token: Application.get_env(:slack, :token),
          attachments: Poison.encode!(eq)
        }
      )
    end

    if not Enum.empty?(lt) do
      Slack.Web.Chat.post_message(
        channel,
        ":woman_in_lotus_position::man_in_lotus_position: 일주일내 마감 목록입니다.",
        %{
          as_user: false,
          token: Application.get_env(:slack, :token),
          attachments: Poison.encode!(lt)
        }
      )
    end
  end

  @spec due_date_attachments(String.t(), [integer]) :: map()
  defp due_date_attachments(gitlab_id, started_milestones) do
    today = Date.utc_today()

    due_dates =
      Gitlab.assigned_issues(gitlab_id)
      |> Enum.map(fn %{"due_date" => date} = issue ->
        case Date.from_iso8601(date || "") do
          {:ok, date} -> %{issue | "due_date" => date}
          _ -> %{issue | "due_date" => nil}
        end
      end)

    {need_due_dates, due_dates} =
      due_dates
      |> Enum.split_with(fn
        %{"due_date" => nil} -> true
        _ -> false
      end)

    need_due_dates =
      need_due_dates
      |> Enum.filter(fn
        %{"milestone" => %{"id" => id}} -> id in started_milestones
        _ -> false
      end)

    # TODO: issue를 가져오는 단계에서 한번 가공한다
    due_dates =
      due_dates
      |> Enum.group_by(&Date.compare(today, &1["due_date"]))

    gt = SlackAdapter.Attachments.from_issues(due_dates[:gt] || [], :due_date)
    eq = SlackAdapter.Attachments.from_issues(due_dates[:eq] || [], :due_date)

    next_due_date = Date.add(today, 7)

    lt =
      (due_dates[:lt] || [])
      |> Enum.filter(fn %{"due_date" => date} ->
        Date.compare(next_due_date, date) in [:gt, :eq]
      end)
      |> SlackAdapter.Attachments.from_issues(:due_date)

    need_due_dates =
      SlackAdapter.Attachments.from_issues(need_due_dates, :summary, color: "#F35A00")

    %{gt: gt, eq: eq, lt: lt, need_due_dates: need_due_dates}
  end

  @spec parse_date(String.t()) :: {:ok, Date.t()} | :error
  defp parse_date(str) do
    date =
      with {delta, ""} <- Integer.parse(str) do
        abs =
          Timex.now()
          |> Timex.Timezone.convert(Timex.Timezone.local())
          |> DateTime.to_date()
          |> Date.add(delta)

        {:ok, abs}
      else
        _ -> :error
      end

    with true <- date == :error,
         {:ok, abs} <- Date.from_iso8601(str) do
      {:ok, abs}
    else
      {:error, _} -> :error
      _ -> date
    end
  end

  @spec mention_string_from_gitlab_id(String.t()) :: String.t()
  defp mention_string_from_gitlab_id(gitlab_id) do
    slack_id =
      Application.get_env(:slab, :gitlab_slack_ids)
      |> Enum.find_value(fn
        {^gitlab_id, slack_id} -> slack_id
        _ -> nil
      end)

    if slack_id do
      "<@#{slack_id}> "
    else
      ""
    end
  end
end
