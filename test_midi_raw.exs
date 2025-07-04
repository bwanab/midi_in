#!/usr/bin/env elixir

Mix.install([
  {:midi_in, path: "."}
])

# Raw MIDI Message Monitor
# Usage: elixir test_midi_raw.exs [device_regex]

defmodule MidiRawTest do
  @moduledoc """
  Raw MIDI message monitor that shows both the original bytes and decoded information.
  Perfect for debugging and understanding MIDI message flow.
  """

  import Bitwise
  require Logger

  def main(args \\ []) do
    device_regex = case args do
      [device] -> device
      [] -> ".*"
      _ ->
        IO.puts("Usage: elixir test_midi_raw.exs [device_regex]")
        System.halt(1)
    end

    IO.puts("🔬 Raw MIDI Monitor Starting...")
    IO.puts("=" |> String.duplicate(60))

    Application.ensure_all_started(:midi_in)
    show_available_devices()

    IO.puts("\n🔍 Connecting to device matching: '#{device_regex}'")

    case MidiIn.get_port(device_regex, :input) do
      {:ok, input_port} ->
        IO.puts("✅ Found device: #{input_port.name}")
        start_raw_monitor(input_port)
      {:error, reason} ->
        IO.puts("❌ Device not found: #{reason}")
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

  defp start_raw_monitor(input_port) do
    case Midiex.Listener.start_link(port: input_port) do
      {:ok, listener_pid} ->
        IO.puts("🎵 Raw MIDI Monitor Active!")
        IO.puts("   Format: [HEX BYTES] | Message Type | Details")
        IO.puts("   Press Ctrl+C to exit")
        IO.puts("-" |> String.duplicate(60))

        # Set up message handler
        handler_fn = fn msg ->
          process_raw_message(msg)
        end

        Midiex.Listener.add_handler(listener_pid, handler_fn)

        # Keep running
        Process.sleep(:infinity)

      {:error, reason} ->
        IO.puts("❌ Failed to start listener: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp process_raw_message(msg) do
    timestamp = :os.system_time(:millisecond)
    hex_bytes = msg.data
                |> Enum.map(&Integer.to_string(&1, 16))
                |> Enum.map(&String.pad_leading(&1, 2, "0"))
                |> Enum.join(" ")

    {message_type, details} = decode_midi_message(msg.data)

    IO.puts("#{timestamp} | [#{hex_bytes}] | #{message_type} | #{details}")
  end

  defp decode_midi_message([status | data]) do
    <<message_type::size(4), channel::size(4)>> = <<status>>

    case message_type <<< 4 do
      0x80 ->
        [note, velocity] = pad_data(data, 2)
        {"Note Off", "Ch#{channel+1} Note#{note} Vel#{velocity}"}

      0x90 ->
        [note, velocity] = pad_data(data, 2)
        if velocity == 0 do
          {"Note Off", "Ch#{channel+1} Note#{note} (vel=0)"}
        else
          {"Note On", "Ch#{channel+1} Note#{note} Vel#{velocity}"}
        end

      0xA0 ->
        [note, pressure] = pad_data(data, 2)
        {"Poly Touch", "Ch#{channel+1} Note#{note} Pressure#{pressure}"}

      0xB0 ->
        [cc_num, value] = pad_data(data, 2)
        cc_name = get_cc_name(cc_num)
        {"Control Change", "Ch#{channel+1} CC#{cc_num}(#{cc_name}) Val#{value}"}

      0xC0 ->
        [program] = pad_data(data, 1)
        {"Program Change", "Ch#{channel+1} Program#{program}"}

      0xD0 ->
        [pressure] = pad_data(data, 1)
        {"Channel Pressure", "Ch#{channel+1} Pressure#{pressure}"}

      0xE0 ->
        [lsb, msb] = pad_data(data, 2)
        bend_value = (msb <<< 7) + lsb - 8192
        {"Pitch Bend", "Ch#{channel+1} Value#{bend_value}"}

      0xF0 ->
        case status do
          0xF0 -> {"System Exclusive", "SysEx data"}
          0xF1 -> {"MIDI Time Code", "Quarter Frame"}
          0xF2 -> {"Song Position", "Pointer"}
          0xF3 -> {"Song Select", "Song#"}
          0xF6 -> {"Tune Request", ""}
          0xF7 -> {"End SysEx", ""}
          0xF8 -> {"Timing Clock", ""}
          0xFA -> {"Start", ""}
          0xFB -> {"Continue", ""}
          0xFC -> {"Stop", ""}
          0xFE -> {"Active Sensing", ""}
          0xFF -> {"Reset", ""}
          _ -> {"System", "Unknown"}
        end

      _ ->
        {"Unknown", "Status: 0x#{Integer.to_string(status, 16)}"}
    end
  end

  defp decode_midi_message([]) do
    {"Empty", "No data"}
  end

  defp pad_data(data, needed_length) do
    (data ++ List.duplicate(0, needed_length))
    |> Enum.take(needed_length)
  end

  defp get_cc_name(cc_num) do
    case cc_num do
      0 -> "Bank Select MSB"
      1 -> "Modulation"
      2 -> "Breath Controller"
      4 -> "Foot Controller"
      5 -> "Portamento Time"
      6 -> "Data Entry MSB"
      7 -> "Volume"
      8 -> "Balance"
      10 -> "Pan"
      11 -> "Expression"
      12 -> "Effect 1"
      13 -> "Effect 2"
      32 -> "Bank Select LSB"
      64 -> "Sustain Pedal"
      65 -> "Portamento"
      66 -> "Sostenuto"
      67 -> "Soft Pedal"
      68 -> "Legato"
      69 -> "Hold 2"
      70 -> "Sound Variation"
      71 -> "Resonance"
      72 -> "Release Time"
      73 -> "Attack Time"
      74 -> "Brightness"
      75 -> "Decay Time"
      76 -> "Vibrato Rate"
      77 -> "Vibrato Depth"
      78 -> "Vibrato Delay"
      120 -> "All Sound Off"
      121 -> "Reset Controllers"
      122 -> "Local Control"
      123 -> "All Notes Off"
      124 -> "Omni Off"
      125 -> "Omni On"
      126 -> "Mono Mode"
      127 -> "Poly Mode"
      _ -> "CC#{cc_num}"
    end
  end
end

case System.argv() do
  args -> MidiRawTest.main(args)
end
