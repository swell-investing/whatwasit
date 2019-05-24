defmodule Whatwasit.Mixfile do
  use Mix.Project

  @version "0.2.2"

  def project do
    [app: :whatwasit,
     version: @version,
     elixir: "~> 1.2",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     docs: [extras: ["README.md"], main: "Whatwasit"],
     deps: deps(),
     package: package(),
     name: "Whatwasit",
     description: """
     Track changes to your Ecto models.
     """ ]
  end

  def application do
    [applications: applications(Mix.env)]
  end

  defp applications(:test), do: [:logger, :ecto, :ecto_sql, :postgrex]
  defp applications(_), do: [:logger, :ecto, :ecto_sql]

  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_),     do: ["lib", "web"]

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:postgrex, ">= 0.0.0", only: :test},
      {:ex_doc, "== 0.11.5", only: :dev},
      {:earmark, "== 0.2.1", only: :dev, override: true},
    ]
  end

  defp package do
    [ maintainers: ["Stephen Pallen"],
      licenses: ["MIT"],
      links: %{ "Github" => "https://github.com/smpallen99/whatwasit" },
      files: ~w(lib priv README.md mix.exs LICENSE)]
  end
end
