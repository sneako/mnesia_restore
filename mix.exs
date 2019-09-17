defmodule MnesiaRestore.MixProject do
  use Mix.Project

  def project do
    [
      app: :mnesia_restore,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  defp deps do
    [
      {:ex_unit_clustered_case, "~> 0.1", only: :test}
    ]
  end
end
