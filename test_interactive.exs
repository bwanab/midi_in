#!/usr/bin/env elixir

# Interactive MidiIn Test Script  
# Usage: elixir test_interactive.exs [device_regex]

defmodule InteractiveMidiTest do
  @moduledoc """
  Interactive test of the MidiIn system with your physical device.
  Tests the complete workflow: device connection, CC registration, message processing.
  """

  def main(args \\ []) do
    device_regex = case args do
      [device] -> device
      [] -> prompt_for_device()
      _ -> 
        IO.puts("Usage: elixir test_interactive.exs [device_regex]")
        System.halt(1)
    end

    IO.puts("🎹 Interactive MidiIn Test")
    IO.puts("=" |> String.duplicate(40))
    
    Application.ensure_all_started(:midi_in)
    
    # Show available devices
    show_devices()
    
    # Start the test
    run_interactive_test(device_regex)
  end

  defp prompt_for_device do
    show_devices()
    IO.puts("\nEnter device name pattern (or press Enter for any device):")
    case IO.gets("Device regex: ") |> String.trim() do
      "" -> ".*"
      device -> device
    end
  end

  defp show_devices do
    IO.puts("\n📱 Available MIDI Input Devices:")
    
    ports = Midiex.ports(:input)
    if Enum.empty?(ports) do
      IO.puts("   ❌ No MIDI input devices found!")
      IO.puts("   Make sure your MIDI device is connected.")
      System.halt(1)
    end
    
    ports
    |> Enum.with_index(1)
    |> Enum.each(fn {port, index} ->
      IO.puts("   #{index}. #{port.name}")
    end)
  end

  defp run_interactive_test(device_regex) do
    IO.puts("\n🔍 Connecting to device matching: '#{device_regex}'")
    
    # Create a test control function that prints everything
    control_function = fn id, control, value ->
      timestamp = DateTime.now!("Etc/UTC") |> DateTime.to_time() |> Time.to_string()
      IO.puts("#{timestamp} | 🎛️  Control: ID=#{id}, Control=#{control}, Value=#{value}")
    end
    
    # Start MIDI connection
    case MidiInClient.start_midi(100, "note", control_function, device_regex) do
      {:ok, listener_pid} ->
        IO.puts("✅ Connected! (Listener: #{inspect(listener_pid)})")
        setup_test_environment()
        run_test_loop()
        
      {:error, reason} ->
        IO.puts("❌ Connection failed: #{reason}")
        System.halt(1)
    end
  end

  defp setup_test_environment do
    IO.puts("\n🎛️  Setting up MIDI environment...")
    
    # Register common MIDI controls
    test_ccs = [
      {1, 101, "modulation"},
      {2, 102, "breath"},
      {7, 107, "volume"},
      {10, 110, "pan"},
      {11, 111, "expression"},
      {64, 164, "sustain"},
      {71, 171, "resonance"},
      {74, 174, "brightness"}
    ]
    
    Enum.each(test_ccs, fn {cc_num, id, name} ->
      result = MidiInClient.register_cc(cc_num, id, name)
      IO.puts("   CC#{cc_num} (#{name}) -> ID#{id}: #{result}")
    end)
    
    # Register some gates for note testing
    Enum.each([201, 202, 203], fn gate_id ->
      result = MidiInClient.register_gate(gate_id)
      IO.puts("   Gate #{gate_id}: #{result}")
    end)
    
    IO.puts("\n✅ Environment ready!")
  end

  defp run_test_loop do
    IO.puts("\n🎵 MIDI Test Active!")
    IO.puts("Try the following on your MIDI device:")
    IO.puts("   🎹 Play notes (watch for note messages and gate triggers)")
    IO.puts("   🎛️  Move controllers/knobs (CC1, CC2, CC7, CC10, CC11, CC64, CC71, CC74)")
    IO.puts("   🎚️  Use pitch bend wheel")
    IO.puts("   🔄 Press sustain pedal (CC64)")
    IO.puts("\nPress 'h' + Enter for help, 'q' + Enter to quit")
    IO.puts("-" |> String.duplicate(50))
    
    input_loop()
  end

  defp input_loop do
    case IO.gets("") |> String.trim() |> String.downcase() do
      "q" -> 
        cleanup_and_exit()
      "quit" -> 
        cleanup_and_exit()
      "h" -> 
        show_help()
        input_loop()
      "help" -> 
        show_help()
        input_loop()
      "s" ->
        show_status()
        input_loop()
      "status" ->
        show_status()
        input_loop()
      "" -> 
        input_loop()  # Empty input, keep going
      unknown ->
        IO.puts("Unknown command: #{unknown}. Press 'h' for help.")
        input_loop()
    end
  end

  defp show_help do
    IO.puts("\n📖 Commands:")
    IO.puts("   h, help   - Show this help")
    IO.puts("   s, status - Show current MIDI status")
    IO.puts("   q, quit   - Exit the test")
    IO.puts("   (empty)   - Continue monitoring")
    IO.puts("")
  end

  defp show_status do
    # Note: We can't easily get the internal state without modifying MidiIn,
    # so we'll just show what we can
    IO.puts("\n📊 MIDI Status:")
    IO.puts("   Connection: Active")
    IO.puts("   Registered CCs: 1,2,7,10,11,64,71,74")
    IO.puts("   Registered Gates: 201,202,203")
    IO.puts("   Monitoring: All MIDI messages")
    IO.puts("")
  end

  defp cleanup_and_exit do
    IO.puts("\n🛑 Stopping MIDI...")
    MidiInClient.stop_midi()
    IO.puts("✅ MIDI stopped. Goodbye!")
    System.halt(0)
  end
end

case System.argv() do
  args -> InteractiveMidiTest.main(args)
end