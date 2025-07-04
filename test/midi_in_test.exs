defmodule MidiInTest do
  use ExUnit.Case
  import TestHelper

  setup do
    # Stop the application-started MidiIn and start a fresh one for each test
    case GenServer.whereis(MidiIn) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
    {:ok, pid} = MidiIn.start_link([])
    {:ok, pid: pid}
  end

  describe "GenServer state management" do
    test "initializes with empty state", %{pid: pid} do
      state = :sys.get_state(pid)
      
      assert state.note_module_id == 0
      assert state.note_control == ""
      assert state.control_function == nil
      assert state.cc_registry == %{}
      assert state.gate_registry == []
      assert state.midi_pid == 0
      assert state.last_note == 0
    end

    test "handle_call :stop terminates GenServer", %{pid: pid} do
      # Get the state before stopping
      state_before = :sys.get_state(pid)
      
      # The :stop call should terminate the GenServer
      catch_exit(GenServer.call(pid, :stop))
      
      # Verify the process is no longer alive
      refute Process.alive?(pid)
    end
  end

  describe "register_cc functionality" do
    test "registers CC control successfully", %{pid: pid} do
      # Set up mock midi_pid to allow CC registration
      state = %MidiIn.State{midi_pid: :mock_pid}
      :sys.replace_state(pid, fn _ -> state end)
      
      result = GenServer.call(pid, {:register_cc, 7, 1, "volume"})
      assert result == :ok
      
      state = :sys.get_state(pid)
      assert Map.has_key?(state.cc_registry, 7)
      assert length(state.cc_registry[7]) == 1
      
      [cc] = state.cc_registry[7]
      assert cc.cc_id == 1
      assert cc.cc_control == "volume"
    end

    test "registers multiple CCs for same number", %{pid: pid} do
      # Set up mock midi_pid to allow CC registration
      state = %MidiIn.State{midi_pid: :mock_pid}
      :sys.replace_state(pid, fn _ -> state end)
      
      GenServer.call(pid, {:register_cc, 7, 1, "volume"})
      GenServer.call(pid, {:register_cc, 7, 2, "gain"})
      
      state = :sys.get_state(pid)
      assert length(state.cc_registry[7]) == 2
      
      cc_ids = Enum.map(state.cc_registry[7], & &1.cc_id)
      assert 1 in cc_ids
      assert 2 in cc_ids
    end

    test "registers CCs for different numbers", %{pid: pid} do
      # Set up mock midi_pid to allow CC registration
      state = %MidiIn.State{midi_pid: :mock_pid}
      :sys.replace_state(pid, fn _ -> state end)
      
      GenServer.call(pid, {:register_cc, 7, 1, "volume"})
      GenServer.call(pid, {:register_cc, 11, 2, "expression"})
      
      state = :sys.get_state(pid)
      assert Map.has_key?(state.cc_registry, 7)
      assert Map.has_key?(state.cc_registry, 11)
      assert length(state.cc_registry[7]) == 1
      assert length(state.cc_registry[11]) == 1
    end

    test "register_cc with no midi returns :no_midi", %{pid: pid} do
      # midi_pid is 0 by default
      result = GenServer.call(pid, {:register_cc, 7, 1, "volume"})
      assert result == :no_midi
    end
  end

  describe "register_gate functionality" do
    test "registers gate successfully", %{pid: pid} do
      result = GenServer.call(pid, {:register_gate, 1})
      assert result == :ok
      
      state = :sys.get_state(pid)
      assert 1 in state.gate_registry
    end

    test "registers multiple gates", %{pid: pid} do
      GenServer.call(pid, {:register_gate, 1})
      GenServer.call(pid, {:register_gate, 2})
      
      state = :sys.get_state(pid)
      assert 1 in state.gate_registry
      assert 2 in state.gate_registry
      assert length(state.gate_registry) == 2
    end

    test "gate registry preserves order", %{pid: pid} do
      GenServer.call(pid, {:register_gate, 1})
      GenServer.call(pid, {:register_gate, 2})
      GenServer.call(pid, {:register_gate, 3})
      
      state = :sys.get_state(pid)
      # Gates are prepended, so order should be [3, 2, 1]
      assert state.gate_registry == [3, 2, 1]
    end
  end

  describe "stop_midi functionality" do
    test "stop_midi resets state", %{pid: pid} do
      # Set up some state first
      GenServer.call(pid, {:register_gate, 1})
      GenServer.call(pid, {:register_gate, 2})
      
      # Stop MIDI
      result = GenServer.call(pid, :stop_midi)
      assert result == :ok
      
      # Check state is reset
      state = :sys.get_state(pid)
      assert state.midi_pid == 0
      assert state.gate_registry == []
    end
  end

  describe "handle_info message processing" do
    test "processes single MIDI message", %{pid: pid} do
      # Set up state for message processing
      state = %MidiIn.State{
        note_module_id: 1,
        note_control: "freq",
        control_function: mock_control_function_for(self()),
        cc_registry: %{},
        gate_registry: [],
        midi_pid: 0,
        last_note: 60
      }
      :sys.replace_state(pid, fn _ -> state end)
      
      # Send a note on message
      message = note_on_message(60, 127)
      send(pid, {:mock_pid, [message]})
      
      # Allow message processing
      Process.sleep(10)
      
      # Check that the message was processed
      new_state = :sys.get_state(pid)
      assert new_state.last_note == 60
      assert_control_called(1, "freq", 60)
    end

    test "processes multiple MIDI messages", %{pid: pid} do
      # Set up state
      cc_registry = %{7 => [%MidiIn.CC{cc_id: 1, cc_control: "volume"}]}
      state = %MidiIn.State{
        note_module_id: 1,
        note_control: "freq",
        control_function: mock_control_function_for(self()),
        cc_registry: cc_registry,
        gate_registry: [],
        midi_pid: 0,
        last_note: 60
      }
      :sys.replace_state(pid, fn _ -> state end)
      
      # Send multiple messages
      messages = [
        note_on_message(60, 127),
        cc_message(7, 64)
      ]
      send(pid, {:mock_pid, messages})
      
      # Allow message processing
      Process.sleep(10)
      
      # Check that both messages were processed
      assert_control_called(1, "freq", 60)
      assert_control_called(1, "volume", 64/127)
    end
  end

  describe "handle_info gate timing" do
    test "handles open_gate message", %{pid: pid} do
      # Set up state with control function
      state = %MidiIn.State{
        control_function: mock_control_function_for(self()),
        note_module_id: 1,
        note_control: "freq",
        cc_registry: %{},
        gate_registry: [],
        midi_pid: 0,
        last_note: 60
      }
      :sys.replace_state(pid, fn _ -> state end)
      
      # Send open_gate message
      send(pid, {:open_gate, 1})
      
      # Allow message processing
      Process.sleep(10)
      
      # Check that gate was opened
      assert_control_called(1, "gate", 1)
    end
  end

  describe "CC struct" do
    test "creates CC struct with correct fields" do
      cc = %MidiIn.CC{cc_id: 1, cc_control: "volume"}
      
      assert cc.cc_id == 1
      assert cc.cc_control == "volume"
    end

    test "CC struct has correct type" do
      cc = %MidiIn.CC{cc_id: 1, cc_control: "volume"}
      assert is_struct(cc, MidiIn.CC)
    end
  end

  describe "State struct" do
    test "creates State struct with correct defaults" do
      state = %MidiIn.State{}
      
      assert state.note_module_id == 0
      assert state.note_control == ""
      assert state.control_function == nil
      assert state.cc_registry == %{}
      assert state.gate_registry == []
      assert state.midi_pid == 0
      assert state.last_note == 0
    end

    test "State struct has correct type" do
      state = %MidiIn.State{}
      assert is_struct(state, MidiIn.State)
    end
  end
end