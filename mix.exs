defmodule Mailroom.Mixfile do
  use Mix.Project

  @github_url "https://github.com/andrewtimberlake/mailroom"
  @version "0.3.0"

  def project do
    [
      app: :mailroom,
      name: "Mailroom",
      version: @version,
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @github_url,
      docs: fn ->
        [
          source_ref: "v#{@version}",
          canonical: "http://hexdocs.pm/mailroom",
          main: "Mailroom",
          source_url: @github_url,
          extras: ["README.md"]
        ]
      end,
      description: description(),
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger, :mail, :ssl]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:mail,
       git: "https://github.com/primait/elixir-mail.git",
       ref: "17cd258340b2e5b58dfb5a2ca7da8d5a9464faa0"},
      # DEV
      {:credo, "~> 1.0", only: :dev},
      # Docs
      {:ex_doc, "~> 0.14", only: [:dev, :docs]},
      {:earmark, "~> 1.0", only: [:dev, :docs]},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    A library for sending, receving and processing emails.
    """
  end

  defp package do
    [
      maintainers: ["Andrew Timberlake"],
      contributors: ["Andrew Timberlake"],
      licenses: ["MIT"],
      links: %{"Github" => @github_url}
    ]
  end
end
