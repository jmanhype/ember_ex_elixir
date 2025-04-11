defmodule EmberEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :ember_ex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {EmberEx.Application, []}
    ]
  end

  defp deps do
    [
      # Using instructor_ex for structured outputs from LLMs
      {:instructor, git: "https://github.com/thmsmlr/instructor_ex.git"},
      # JSON parsing
      {:jason, "~> 1.4"},
      # Schema validation
      {:ecto, "~> 3.10"},
      # HTTP clients
      {:finch, "~> 0.16"},
      {:httpoison, "~> 2.1"},
      # Testing
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:meck, "~> 0.9.2", only: :test}
    ]
  end
end
