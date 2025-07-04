defmodule MessageProcessingTest do
  use ExUnit.Case
  import TestHelper

  describe "process_message/2" do
    test "handles note on message with velocity > 0" do
      state = create_test_state(%{note_module_id: 1, note_control: "freq"})
      message = note_on_message(60, 127)

      result = MidiIn.process_message(message, state)

      assert result.last_note == 60
      assert_control_called(1, "freq", 60)
    end

    test "handles note on message with velocity 0 (note off)" do
      state = create_test_state(%{last_note: 60})
      message = note_on_message(60, 0)

      result = MidiIn.process_message(message, state)

      # Note off should not change last_note
      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "note on with note_module_id = 0 does nothing" do
      state = create_test_state(%{note_module_id: 0})
      message = note_on_message(60, 127)

      result = MidiIn.process_message(message, state)

      assert result.last_note == 60  # unchanged from initial state
      assert_no_control_calls()
    end

    test "note on triggers gate sequence" do
      gate_registry = [1, 2]
      state = create_test_state(%{
        note_module_id: 1,
        note_control: "freq",
        gate_registry: gate_registry
      })
      message = note_on_message(60, 127)

      MidiIn.process_message(message, state)

      # Should set gates to 0 immediately
      assert_control_called(1, "gate", 0)
      assert_control_called(2, "gate", 0)
    end

    test "handles note off message" do
      state = create_test_state(%{last_note: 60})
      message = note_off_message(60, 64)

      result = MidiIn.process_message(message, state)

      # Note off should not change last_note
      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "handles CC message with registered control" do
      cc_registry = %{7 => [%MidiIn.CC{cc_id: 1, cc_control: "volume"}]}
      state = create_test_state(%{cc_registry: cc_registry})
      message = cc_message(7, 64)

      MidiIn.process_message(message, state)

      # CC value should be normalized to 0-1 range
      assert_control_called(1, "volume", 64/127)
    end

    test "handles CC message with multiple registered controls" do
      cc_registry = %{7 => [
        %MidiIn.CC{cc_id: 1, cc_control: "volume"},
        %MidiIn.CC{cc_id: 2, cc_control: "gain"}
      ]}
      state = create_test_state(%{cc_registry: cc_registry})
      message = cc_message(7, 127)

      MidiIn.process_message(message, state)

      assert_control_called(1, "volume", 1.0)
      assert_control_called(2, "gain", 1.0)
    end

    test "handles CC message with unregistered control" do
      state = create_test_state(%{cc_registry: %{}})
      message = cc_message(7, 64)

      result = MidiIn.process_message(message, state)

      # Should not change state or call controls
      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "handles pitch bend message" do
      state = create_test_state(%{
        note_module_id: 1,
        note_control: "freq",
        last_note: 60
      })
      # Center pitch bend: lsb=0, msb=64 (8192 total)
      message = pitch_bend_message(0, 64)

      MidiIn.process_message(message, state)

      # Center bend should result in no change (bend = 0)
      assert_control_called(1, "freq", 60.0)
    end

    test "handles pitch bend with positive bend" do
      state = create_test_state(%{
        note_module_id: 1,
        note_control: "freq",
        last_note: 60
      })
      # Max positive bend: lsb=127, msb=127 (16383 total)
      message = pitch_bend_message(127, 127)

      MidiIn.process_message(message, state)

      # Max bend should be (16383 - 8192) / 4000 = ~2.05
      expected_freq = 60 + (16383 - 8192) / 4000.0
      assert_control_called(1, "freq", expected_freq)
    end

    test "handles pitch bend with negative bend" do
      state = create_test_state(%{
        note_module_id: 1,
        note_control: "freq",
        last_note: 60
      })
      # Min negative bend: lsb=0, msb=0 (0 total)
      message = pitch_bend_message(0, 0)

      MidiIn.process_message(message, state)

      # Min bend should be (0 - 8192) / 4000 = -2.048
      expected_freq = 60 + (0 - 8192) / 4000.0
      assert_control_called(1, "freq", expected_freq)
    end

    test "pitch bend with note_module_id = 0 does nothing" do
      state = create_test_state(%{note_module_id: 0, last_note: 60})
      message = pitch_bend_message(0, 64)

      result = MidiIn.process_message(message, state)

      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "handles program change message" do
      state = create_test_state(%{last_note: 60})
      message = program_change_message(42)

      result = MidiIn.process_message(message, state)

      # Program change should not change last_note
      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "handles channel pressure message" do
      state = create_test_state(%{cc_registry: %{2 => [%MidiIn.CC{cc_id: 1, cc_control: "pressure"}]}})
      # Channel pressure: status 0xD0, data1=pressure value, data2=0
      message = create_midi_message(0xD0, 100, 0)

      MidiIn.process_message(message, state)

      # Channel pressure should call set_vol with cc_num=2
      assert_control_called(1, "pressure", 100/127)
    end

    test "handles polyphonic aftertouch message" do
      state = create_test_state(%{last_note: 60})
      # Polyphonic aftertouch: status 0xA0, note, pressure
      message = create_midi_message(0xA0, 60, 100)

      result = MidiIn.process_message(message, state)

      # Should not change last_note
      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "handles system exclusive message" do
      state = create_test_state(%{last_note: 60})
      message = create_midi_message(0xF0, 0, 0)

      result = MidiIn.process_message(message, state)

      # Should not change last_note
      assert result.last_note == 60
      assert_no_control_calls()
    end

    test "handles unknown status byte" do
      state = create_test_state(%{last_note: 60})
      message = create_midi_message(0xFF, 0, 0)

      result = MidiIn.process_message(message, state)

      # Should not change last_note for unknown status
      assert result.last_note == 60
      assert_no_control_calls()
    end
  end

  describe "set_vol/4" do
    test "calls control function for registered CC" do
      cc_registry = %{7 => [%MidiIn.CC{cc_id: 1, cc_control: "volume"}]}
      state = create_test_state(%{cc_registry: cc_registry})

      MidiIn.set_vol(state, 7, 127, &mock_control_function/3)

      assert_control_called(1, "volume", 1.0)
    end

    test "handles multiple CCs for same number" do
      cc_registry = %{7 => [
        %MidiIn.CC{cc_id: 1, cc_control: "volume"},
        %MidiIn.CC{cc_id: 2, cc_control: "gain"}
      ]}
      state = create_test_state(%{cc_registry: cc_registry})

      MidiIn.set_vol(state, 7, 64, &mock_control_function/3)

      assert_control_called(1, "volume", 64/127)
      assert_control_called(2, "gain", 64/127)
    end

    test "does nothing for unregistered CC" do
      state = create_test_state(%{cc_registry: %{}})

      MidiIn.set_vol(state, 7, 64, &mock_control_function/3)

      assert_no_control_calls()
    end

    test "normalizes CC values to 0-1 range" do
      cc_registry = %{7 => [%MidiIn.CC{cc_id: 1, cc_control: "volume"}]}
      state = create_test_state(%{cc_registry: cc_registry})

      MidiIn.set_vol(state, 7, 0, &mock_control_function/3)
      assert_control_called(1, "volume", 0.0)

      flush_control_calls()

      MidiIn.set_vol(state, 7, 127, &mock_control_function/3)
      assert_control_called(1, "volume", 1.0)
    end
  end
end