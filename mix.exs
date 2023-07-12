defmodule K8sWebhoox.MixProject do
  use Mix.Project
  @version "0.2.0"
  @source_url "https://github.com/mruoss/k8s_webhoox"

  def project do
    [
      app: :k8s_webhoox,
      description: description(),
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: cli_env(),
      test_coverage: [tool: ExCoveralls],
      docs: docs(),
      package: package()
    ]
  end

  defp cli_env do
    [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test,
      "coveralls.travis": :test,
      "coveralls.github": :test,
      "coveralls.xml": :test,
      "coveralls.json": :test
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:k8s, "~> 2.0"},
      {:plug, "~> 1.0"},
      {:pluggable, "~> 1.0"},
      {:x509, "~> 0.8.5"},
      {:yaml_elixir, "~> 2.0"},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.16", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      assets: "assets",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: :k8s_webhoox,
      maintainers: ["Michael Ruoss"],
      licenses: ["Apache"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "GitHub" => @source_url
      },
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"]
    ]
  end

  defp description do
    """
    Kubernetes Webhooks SDK for Elixir.
    """
  end
end
