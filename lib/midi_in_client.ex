defmodule MidiInClient do
  require Logger
  def start_midi(synth, param, control_function) do
    GenServer.call(MidiIn, {:start_midi, "mio", synth, param, control_function})
  end

  def register_cc(cc_num, cc, control) do
    GenServer.call(MidiIn, {:register_cc, cc_num, cc, control})
  end

  def register_gate(id) do
    GenServer.call(MidiIn, {:register_gate, id})
  end

  def register_gate(pid, id) do
    GenServer.call(pid, {:register_gate, id})
  end

  def stop_midi() do
    if Logger.level() == :debug do
      Logger.debug("In stop_midi")
      stacktrace = Process.info(self(), :current_stacktrace)
      IO.inspect(stacktrace)
    end
    GenServer.call(MidiIn, :stop_midi)
  end
end
