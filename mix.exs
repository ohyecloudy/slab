defmodule GitlabStraw.MixProject do
  use Mix.Project

  def project do
    [
      app: :gitlab_straw,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GitlabStraw.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:slack, "~> 0.14.0"},
      {:httpoison, "~> 1.1", override: true}
    ]
  end
end
