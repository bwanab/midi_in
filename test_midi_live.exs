#!/usr/bin/env elixir

Mix.install([
  {:midi_in, path: "."}
])

# Live MIDI Test Script
# Usage: elixir test_midi_live.exs [device_regex]
# Example: elixir test_midi_live.exs "AE-30"

defmodule MidiLiveTest do
  @moduledoc """
  Interactive script to test MIDI input with your physical device.
  Connects to your MIDI device and prints all incoming messages in real-time.
  """

  require Logger

  def main(args \\ []) do
    device_regex = case args do
      [device] -> device
      [] -> ".*"  # Match any device
      _ ->
        IO.puts("Usage: elixir test_midi_live.exs [device_regex]")
        System.halt(1)
    end

    IO.puts("🎹 MIDI Live Test Starting...")
    IO.puts("=" |> String.duplicate(50))

    # Start the application
    Application.ensure_all_started(:midi_in)

    # List available MIDI devices
    show_available_devices()

    IO.puts("\n🔍 Looking for MIDI device matching: '#{device_regex}'")

    # Create a message printer function
    message_printer = fn id, control, value ->
      timestamp = :os.system_time(:millisecond)
      IO.puts("#{timestamp} | Control: id=#{id}, control=#{control}, value=#{value}")
    end

    # Start MIDI with the device
    case MidiInClient.start_midi(1, "note", message_printer, device_regex) do
      {:ok, listener_pid} ->
        IO.puts("✅ Connected to MIDI device! (Listener PID: #{inspect(listener_pid)})")
        IO.puts("🎵 Play your MIDI device - messages will appear below:")
        IO.puts("   (Press Ctrl+C to exit)")
        IO.puts("-" |> String.duplicate(50))

        # Register some common CCs for testing
        setup_common_ccs()

        # Keep the script running
        keep_alive()

      {:error, reason} ->
        IO.puts("❌ Failed to connect to MIDI device: #{reason}")
        IO.puts("\n💡 Try:")
        IO.puts("   - Check your MIDI device is connected")
        IO.puts("   - Try a different device regex pattern")
        IO.puts("   - Use 'elixir test_midi_live.exs' to see all devices")
        System.halt(1)
    end
  end

  defp show_available_devices do
    IO.puts("\n📱 Available MIDI Input Devices:")

    case Midiex.ports(:input) do
      [] ->
        IO.puts("   (No MIDI input devices found)")
      ports ->
        ports
        |> Enum.with_index(1)
        |> Enum.each(fn {port, index} ->
          IO.puts("   #{index}. #{port.name}")
        end)
    end
  end

  defp setup_common_ccs do
    # Register common MIDI CCs for testing
    common_ccs = [
      {1, "modulation"},
      {2, "breath"},
      {7, "volume"},
      {10, "pan"},
      {11, "expression"},
      {64, "sustain"},
      {65, "portamento"},
      {66, "sostenuto"},
      {67, "soft_pedal"},
      {71, "resonance"},
      {72, "release_time"},
      {73, "attack_time"},
      {74, "brightness"}
    ]

    Enum.each(common_ccs, fn {cc_num, cc_name} ->
      MidiInClient.register_cc(cc_num, cc_num, cc_name)
    end)

    # Register a gate for note on/off messages
    MidiInClient.register_gate(999)

    IO.puts("🎛️  Registered common MIDI CCs (volume, modulation, etc.)")
  end

  defp keep_alive do
    # Create a simple loop that prints a heartbeat every 30 seconds
    spawn(fn -> heartbeat_loop() end)

    # Main process sleeps forever
    Process.sleep(:infinity)
  end

  defp heartbeat_loop do
    Process.sleep(30_000)
    IO.puts("💓 MIDI monitor active... (#{DateTime.now!("Etc/UTC") |> DateTime.to_time() |> Time.to_string()})")
    heartbeat_loop()
  end
end

# Start the script
case System.argv() do
  args -> MidiLiveTest.main(args)
end
