ExUnit.start()

defmodule TestHelper do
  import ExUnit.Assertions
  @moduledoc """
  Helper utilities for testing MIDI functionality without external devices.
  """

  @doc """
  Mock control function that captures calls for testing.
  Sends a message to the test process with the call details.
  """
  def mock_control_function(id, control, value) do
    # Get the test PID from the process dictionary
    case Process.get(:test_pid) do
      nil -> :ok  # No test PID set, just return ok
      test_pid -> send(test_pid, {:control_called, id, control, value})
    end
    :ok
  end

  @doc """
  Creates a mock control function that sends messages to a specific PID.
  """
  def mock_control_function_for(test_pid) do
    fn id, control, value ->
      send(test_pid, {:control_called, id, control, value})
      :ok
    end
  end

  @doc """
  Silent mock control function that doesn't send messages.
  Useful for tests that don't need to verify control calls.
  """
  def silent_mock_control_function(_id, _control, _value), do: :ok

  @doc """
  Creates a basic test state with mock control function.
  """
  def create_test_state(overrides \\ %{}) do
    base_state = %MidiIn.State{
      note_module_id: 1,
      note_control: "freq",
      control_function: mock_control_function_for(self()),
      cc_registry: %{},
      gate_registry: [],
      listener_pid: nil,
      input_port: nil,
      last_note: 60
    }
    
    struct(base_state, overrides)
  end

  @doc """
  Creates a MIDI message tuple for testing (legacy format).
  """
  def create_midi_message(status, data1, data2, timestamp \\ 0) do
    {{status, data1, data2}, timestamp}
  end

  @doc """
  Creates a Midiex-style MIDI message for testing.
  """
  def create_midiex_message(status, data1, data2, timestamp \\ 0) do
    %{data: [status, data1, data2], timestamp: timestamp}
  end

  @doc """
  Creates a Midiex-style MIDI message with variable data length.
  """
  def create_midiex_message(data_list, timestamp \\ 0) when is_list(data_list) do
    %{data: data_list, timestamp: timestamp}
  end

  @doc """
  Creates common MIDI messages for testing.
  """
  def note_on_message(note, velocity \\ 127, channel \\ 0) do
    status = 0x90 + channel
    create_midi_message(status, note, velocity)
  end

  def note_off_message(note, velocity \\ 64, channel \\ 0) do
    status = 0x80 + channel
    create_midi_message(status, note, velocity)
  end

  def cc_message(cc_num, value, channel \\ 0) do
    status = 0xB0 + channel
    create_midi_message(status, cc_num, value)
  end

  def pitch_bend_message(lsb, msb, channel \\ 0) do
    status = 0xE0 + channel
    create_midi_message(status, lsb, msb)
  end

  def program_change_message(program, channel \\ 0) do
    status = 0xC0 + channel
    create_midi_message(status, program, 0)
  end

  @doc """
  Creates common Midiex MIDI messages for testing.
  """
  def midiex_note_on_message(note, velocity \\ 127, channel \\ 0) do
    status = 0x90 + channel
    create_midiex_message(status, note, velocity)
  end

  def midiex_note_off_message(note, velocity \\ 64, channel \\ 0) do
    status = 0x80 + channel
    create_midiex_message(status, note, velocity)
  end

  def midiex_cc_message(cc_num, value, channel \\ 0) do
    status = 0xB0 + channel
    create_midiex_message(status, cc_num, value)
  end

  def midiex_pitch_bend_message(lsb, msb, channel \\ 0) do
    status = 0xE0 + channel
    create_midiex_message(status, lsb, msb)
  end

  def midiex_program_change_message(program, channel \\ 0) do
    status = 0xC0 + channel
    create_midiex_message(status, program, 0)
  end

  @doc """
  Asserts that a control function was called with specific parameters.
  """
  def assert_control_called(id, control, value) do
    receive do
      {:control_called, ^id, ^control, ^value} -> :ok
    after
      100 -> 
        flunk("Expected control call with id=#{id}, control=#{control}, value=#{value}, but none received")
    end
  end

  @doc """
  Asserts that no control function calls were made.
  """
  def assert_no_control_calls do
    receive do
      {:control_called, _, _, _} = msg -> 
        flunk("Expected no control calls, but received: #{inspect(msg)}")
    after
      10 -> :ok
    end
  end

  @doc """
  Flushes any pending control call messages.
  """
  def flush_control_calls do
    receive do
      {:control_called, _, _, _} -> flush_control_calls()
    after
      0 -> :ok
    end
  end
end