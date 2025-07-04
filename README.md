# MidiIn - Elixir MIDI Input Library

A powerful Elixir library for MIDI input processing with support for Control Change (CC) mapping, gate management, and real-time message processing. Now powered by **Midiex** for modern, cross-platform MIDI support.

## Features

- 🎹 **Real-time MIDI input** with regex-based device matching
- 🎛️ **CC Registry** - Map MIDI Control Change messages to custom controls
- 🎵 **Gate Management** - Handle note on/off with automatic gate timing
- 🎚️ **Pitch Bend Processing** - Full pitch bend calculation and mapping
- 🔄 **Custom Control Functions** - Route MIDI to your application logic
- 🧪 **Comprehensive Testing** - 54 tests covering all functionality

## Quick Start

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:midi_in, path: "../midi_in"}  # or from hex when published
  ]
end
```

### Basic Usage

```elixir
# Start MIDI input with a device (regex pattern)
{:ok, listener_pid} = MidiInClient.start_midi(
  1,                    # synth/module ID  
  "note",              # note control name
  &my_control_fn/3,    # control function
  "AE-30"              # device regex pattern
)

# Register MIDI CC mappings
MidiInClient.register_cc(7, 1, "volume")     # CC7 -> ID1, "volume"
MidiInClient.register_cc(1, 1, "modulation") # CC1 -> ID1, "modulation"

# Register gate triggers for note on/off
MidiInClient.register_gate(1)

# Your control function receives all MIDI events
def my_control_fn(id, control, value) do
  IO.puts("Control: ID=#{id}, Control=#{control}, Value=#{value}")
end

# Stop MIDI when done
MidiInClient.stop_midi()
```

## Testing with Physical MIDI Device

Three test scripts are provided to test with your physical MIDI device:

### 1. Interactive Test (Recommended)
```bash
elixir test_interactive.exs "AE-30"
```
- Full MidiIn system test
- Shows registered CCs and gates working
- Interactive commands (help, status, quit)

### 2. Live MIDI Monitor  
```bash
elixir test_midi_live.exs "AE-30"
```
- Simple real-time MIDI message display
- Uses MidiIn's control function system
- Auto-registers common MIDI CCs

### 3. Raw MIDI Monitor
```bash
elixir test_midi_raw.exs "AE-30"
```
- Shows raw MIDI bytes and decoded messages
- Detailed MIDI message analysis
- Perfect for debugging

### Device Discovery
```bash
elixir test_interactive.exs
# Will show available devices and prompt for selection
```

## API Reference

### Starting MIDI Input

```elixir
MidiInClient.start_midi(synth_id, note_control, control_function, device_regex)
```

- `synth_id`: Integer ID for the synthesizer/module
- `note_control`: String name for note control (e.g., "freq", "note")  
- `control_function`: Function `(id, control, value) -> any`
- `device_regex`: Regex pattern to match MIDI device name

### Control Change Registration

```elixir
MidiInClient.register_cc(cc_number, control_id, control_name)
```

- `cc_number`: MIDI CC number (0-127)
- `control_id`: Your application's control ID
- `control_name`: String name for the control

### Gate Registration

```elixir
MidiInClient.register_gate(gate_id)
```

Gates automatically trigger on note-on events:
1. Set gate to 0 immediately  
2. Set gate to 1 after 50ms delay

### Stopping MIDI

```elixir
MidiInClient.stop_midi()
```

## MIDI Message Processing

The library processes these MIDI message types:

- **Note On/Off** (0x80-0x9F): Triggers control function and gates
- **Control Change** (0xB0-0xBF): Maps to registered CC controls  
- **Pitch Bend** (0xE0-0xEF): Calculates bend value and updates note control
- **Program Change** (0xC0-0xCF): Logged but not processed
- **Channel Pressure** (0xD0-0xDF): Mapped to CC#2
- **Other**: Logged with warnings

Values are automatically normalized:
- **CC Values**: 0-127 → 0.0-1.0
- **Pitch Bend**: -8192 to 8191 → -2.048 to 2.048 (added to note)

## Architecture

Built on **Midiex** for:
- ✅ Cross-platform MIDI support (macOS, Linux, Windows)
- ✅ Real-time performance with Rust backend
- ✅ Modern Elixir integration
- ✅ Hot-plugging device support
- ✅ No native compilation issues

## Development

### Running Tests
```bash
mix test                    # All tests
mix test --max-cases 1      # Sequential execution
```

### Test Coverage
- **54 tests** covering all functionality
- Message processing logic validation
- State management verification  
- API contract testing
- Error scenario handling

## Migration from PortMidi

This library was migrated from PortMidi to Midiex:

- ✅ **API preserved**: Existing code should work unchanged
- ✅ **Regex device matching**: More flexible than fixed device names
- ✅ **Better error messages**: Clear device discovery feedback
- ✅ **Modern foundation**: Future-proof MIDI support

## License

[Your License Here]