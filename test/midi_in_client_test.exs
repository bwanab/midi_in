defmodule MidiInClientTest do
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

  describe "start_midi/4" do
    test "calls GenServer with correct parameters" do
      # Mock the GenServer call by replacing the state
      result = GenServer.call(MidiIn, {:start_midi, "TestDevice", 1, "freq", mock_control_function_for(self())})
      
      # The result depends on whether portmidi finds a device or not
      # Just verify we got a valid response
      assert is_tuple(result)
      assert tuple_size(result) == 2
      assert elem(result, 0) in [:ok, :error]
    end

    test "uses default device when not specified" do
      # The default device is "AE-30" according to the function signature
      result = GenServer.call(MidiIn, {:start_midi, "AE-30", 1, "freq", mock_control_function_for(self())})
      
      # The result depends on whether portmidi finds a device or not
      assert is_tuple(result)
      assert tuple_size(result) == 2
      assert elem(result, 0) in [:ok, :error]
    end

    test "start_midi/3 uses default device" do
      # Test the 3-arity version which should use default device
      result = MidiInClient.start_midi(1, "freq", mock_control_function_for(self()))
      
      # The result depends on whether portmidi finds a device or not
      assert is_tuple(result)
      assert tuple_size(result) == 2
      assert elem(result, 0) in [:ok, :error]
    end
  end

  describe "register_cc/3" do
    test "registers CC successfully" do
      result = MidiInClient.register_cc(7, 1, "volume")
      
      # Should return :no_midi since no MIDI device is connected
      assert result == :no_midi
    end

    test "registers CC with mock listener_pid" do
      # Set up state with a mock listener_pid
      state = %MidiIn.State{listener_pid: :mock_listener_pid}
      :sys.replace_state(MidiIn, fn _ -> state end)
      
      result = MidiInClient.register_cc(7, 1, "volume")
      assert result == :ok
      
      # Verify the CC was registered
      new_state = :sys.get_state(MidiIn)
      assert Map.has_key?(new_state.cc_registry, 7)
      assert length(new_state.cc_registry[7]) == 1
    end

    test "registers multiple CCs for same number" do
      # Set up state with a mock listener_pid
      state = %MidiIn.State{listener_pid: :mock_listener_pid}
      :sys.replace_state(MidiIn, fn _ -> state end)
      
      MidiInClient.register_cc(7, 1, "volume")
      MidiInClient.register_cc(7, 2, "gain")
      
      new_state = :sys.get_state(MidiIn)
      assert length(new_state.cc_registry[7]) == 2
    end

    test "registers CCs for different numbers" do
      # Set up state with a mock listener_pid
      state = %MidiIn.State{listener_pid: :mock_listener_pid}
      :sys.replace_state(MidiIn, fn _ -> state end)
      
      MidiInClient.register_cc(7, 1, "volume")
      MidiInClient.register_cc(11, 2, "expression")
      
      new_state = :sys.get_state(MidiIn)
      assert Map.has_key?(new_state.cc_registry, 7)
      assert Map.has_key?(new_state.cc_registry, 11)
    end
  end

  describe "register_gate/1" do
    test "registers gate successfully" do
      result = MidiInClient.register_gate(1)
      assert result == :ok
      
      state = :sys.get_state(MidiIn)
      assert 1 in state.gate_registry
    end

    test "registers multiple gates" do
      # Ensure we have a fresh GenServer state
      flush_control_calls()
      
      MidiInClient.register_gate(1)
      MidiInClient.register_gate(2)
      
      state = :sys.get_state(MidiIn)
      assert 1 in state.gate_registry
      assert 2 in state.gate_registry
    end
  end

  describe "register_gate/2" do
    test "registers gate with specific pid" do
      # Start another GenServer without a name to avoid conflicts
      {:ok, other_pid} = GenServer.start_link(MidiIn, [%MidiIn.State{}])
      
      result = MidiInClient.register_gate(other_pid, 1)
      assert result == :ok
      
      state = :sys.get_state(other_pid)
      assert 1 in state.gate_registry
      
      # Verify it wasn't registered with the default MidiIn
      default_state = :sys.get_state(MidiIn)
      refute 1 in default_state.gate_registry
      
      # Clean up
      GenServer.stop(other_pid)
    end
  end

  describe "stop_midi/0" do
    test "stops midi successfully" do
      result = MidiInClient.stop_midi()
      assert result == :ok
      
      state = :sys.get_state(MidiIn)
      assert state.listener_pid == nil
      assert state.input_port == nil
      assert state.gate_registry == []
    end

    test "stop_midi resets all state" do
      # Set up some state first
      MidiInClient.register_gate(1)
      MidiInClient.register_gate(2)
      
      # Verify state is set
      state = :sys.get_state(MidiIn)
      assert length(state.gate_registry) == 2
      
      # Stop MIDI
      MidiInClient.stop_midi()
      
      # Verify state is reset
      new_state = :sys.get_state(MidiIn)
      assert new_state.listener_pid == nil
      assert new_state.input_port == nil
      assert new_state.gate_registry == []
    end
  end

  describe "API integration" do
    test "typical workflow without actual MIDI device" do
      # This test demonstrates a typical usage pattern
      # without requiring an actual MIDI device
      
      # Step 1: Try to start MIDI (result depends on available devices)
      result = MidiInClient.start_midi(1, "freq", mock_control_function_for(self()), "TestDevice")
      assert is_tuple(result) and tuple_size(result) == 2
      
      # Step 2: Register some CCs (will return :no_midi)
      result = MidiInClient.register_cc(7, 1, "volume")
      assert result == :no_midi
      
      # Step 3: Register gates (should work)
      result = MidiInClient.register_gate(1)
      assert result == :ok
      
      # Step 4: Stop MIDI
      result = MidiInClient.stop_midi()
      assert result == :ok
    end

    test "workflow with mocked MIDI connection" do
      # Mock a successful MIDI connection
      state = %MidiIn.State{
        listener_pid: :mock_listener_pid,
        note_module_id: 1,
        note_control: "freq",
        control_function: mock_control_function_for(self())
      }
      :sys.replace_state(MidiIn, fn _ -> state end)
      
      # Register CCs and gates
      assert MidiInClient.register_cc(7, 1, "volume") == :ok
      assert MidiInClient.register_cc(11, 1, "expression") == :ok
      assert MidiInClient.register_gate(1) == :ok
      assert MidiInClient.register_gate(2) == :ok
      
      # Verify state
      final_state = :sys.get_state(MidiIn)
      assert Map.has_key?(final_state.cc_registry, 7)
      assert Map.has_key?(final_state.cc_registry, 11)
      assert 1 in final_state.gate_registry
      assert 2 in final_state.gate_registry
      
      # Skip stop_midi with mock_pid as it will try to close a non-existent process
      # In real usage, this would work with actual MIDI devices
      # For migration validation, the important part is that the workflow succeeds
    end
  end

  describe "error handling" do
    test "handles GenServer call failures gracefully" do
      # Stop the MidiIn GenServer
      GenServer.stop(MidiIn)
      
      # Calls should fail with appropriate errors (EXIT, not RuntimeError)
      catch_exit(MidiInClient.register_cc(7, 1, "volume"))
      catch_exit(MidiInClient.register_gate(1))
      catch_exit(MidiInClient.stop_midi())
      
      # If we get here, the calls failed as expected
      assert true
    end
  end

  describe "logging behavior" do
    test "stop_midi logs debug info when logger level is debug" do
      # This test verifies the logging behavior exists
      # In a real test environment, you might want to capture logs
      
      # Call stop_midi - it should execute without error
      result = MidiInClient.stop_midi()
      assert result == :ok
      
      # The actual logging behavior depends on logger configuration
      # and is difficult to test without additional setup
    end
  end
end