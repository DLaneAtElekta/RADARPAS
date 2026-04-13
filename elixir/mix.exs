defmodule Radarpas.MixProject do
  use Mix.Project

  def project do
    [
      app: :radarpas,
      version: "2.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "RADARPAS Weather Radar Display System - Elixir Port",
      docs: [main: "Radarpas"]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Radarpas.Application, []}
    ]
  end

  defp deps do
    [
      # Serial port communication (equivalent to Pascal RS232 routines)
      {:circuits_uart, "~> 1.5"},
      # Testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
