# 설정 파일 샘플
# _config.exs 파일을 config.exs 파일로 복사해서 설정

use Mix.Config

config :slab, enable_poor_gitlab_issue_purling: true

config :slab, :gitlab,
  url: "https://gitlab.com/ohyecloudy/gitlab-straw",
  # project id는 gitlab > Settings > General > General project settings 참고
  api_base_url: "https://gitlab.com/api/v4/projects/12345678",
  # private access token은 gitlab > User Settings > Access Tokens 참고
  private_token: "TOKEN 여기에",
  timeout_ms: 8000

config :slab, :aliases,
  열린이슈!: "issues %{\"state\" => \"opened\"}",
  닫힌이슈!: "issues %{\"state\" => \"closed\"}"

# OAuth & Permissions > Bot User OAuth Access Token
config :slack, token: "TOKEN 여기에"
