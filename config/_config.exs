# 설정 파일 샘플
# _config.exs 파일을 config.exs 파일로 복사해서 설정

use Mix.Config

config :slab,
  enable_poor_gitlab_issue_purling: true,
  enable_poor_gitlab_mr_purling: true

config :slab, :gitlab,
  url: "https://gitlab.com/ohyecloudy/gitlab-straw",
  # project id는 gitlab > Settings > General > General project settings 참고
  api_base_url: "https://gitlab.com/api/v4/projects/12345678",
  # private access token은 gitlab > User Settings > Access Tokens 참고
  private_token: "TOKEN 여기에",
  timeout_ms: 8000

# master 권한을 가진 slack user
config :slab, masters: ["ohyecloudy"]

# :pipeline_watcher 설정이 없으면 파이프라인 감시 기능이 꺼진다
config :slab, :pipeline_watcher,
  # 파이프라인 상태를 감시할 브랜치 이름 리스트
  target_branch_list: ["master"],
  # polling 주기
  poll_changes_interval_ms: 1000 * 60 * 10,
  # 결과를 통보할 slack 채널 이름
  notify_stack_channel_name: "#general",
  # 결과를 통보할 파이프라인 상태(:still_failing, :fixed, :failed, :success)
  notify_pipeline_status: [:still_failing, :fixed, :failed, :success]

# @slab pipelines --branch <branch_name>
# 명령으로 출력할 파이프라인 사용자 필터를 정의할 수 있다
# 입력은 gitlab api 참고
#   https://docs.gitlab.com/ee/api/pipelines.html#get-a-single-pipeline
#
# 아래는 5분 이상 걸린 파이프라인만 출력하는 예제
# config :slab,
#   pipeline_custom_filter: fn %{"duration" => duration, "status" => status} ->
#     cond do
#       status == "failed" ->
#         true

#       status == "running" ->
#         true

#       # 5분 이상 걸린 pipeline
#       duration && duration > 300 ->
#         true

#       true ->
#         false
#     end
#   end

config :slab, :aliases,
  열린이슈!: "issues %{\"state\" => \"opened\"}",
  닫힌이슈!: "issues %{\"state\" => \"closed\"}"

# OAuth & Permissions > Bot User OAuth Access Token
config :slack, token: "TOKEN 여기에"

# gitlab과 slack id를 튜플로 정의해 연결한다.
# slack profile 보기에서 Copy member ID를 눌러서 id를 복사한다.
# [{"ohyecloudy", "acbdwe"}]
config :slab, gitlab_slack_ids: []

config :logger,
  backends: [:console, Sentry.LoggerBackend, {LoggerFileBackend, :file_log}]

config :sentry,
  dsn: "https://public_key@app.getsentry.com/1",
  environment_name: Mix.env(),
  included_environments: [:dev, :prod],
  enable_source_code_context: true,
  root_source_code_path: File.cwd!()

config :logger, :file_log,
  path: "log/slab.log",
  level: :info
