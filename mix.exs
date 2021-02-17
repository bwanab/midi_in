defmodule MidiIn.MixProject do
  use Mix.Project

  def project do
    [
      app: :midi_in,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:portmidi],
      extra_applications: [:logger],
      mod: {MidiIn, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:portmidi, git: "https://github.com/bwanab/ex-portmidi.git"}
    ]
  end
end
