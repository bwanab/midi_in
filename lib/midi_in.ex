defmodule MidiIn.CC do
  defstruct cc_id: 0,
    cc_control: ""
  @type t :: %__MODULE__{cc_id: integer,
                         cc_control: String.t
  }
end

defmodule MidiIn.State do
  defstruct note_module_id: 0,
    note_control: "",
    control_function: nil,
    cc_registry: %{},
    gate_registry: [],
    midi_pid: 0,
    last_note: 0
  @type t :: %__MODULE__{note_module_id: integer,
                         note_control: String.t,
                         control_function: function,
                         cc_registry: map,
                         gate_registry: list,
                         midi_pid: integer,
                         last_note: integer
  }
end



defmodule MidiIn do
  use Application
  use GenServer
  import Bitwise
  require Logger
  alias MidiIn.State

  @impl true
  def start(_type, _args) do
    MidiIn.Supervisor.start_link(name: MidiIn.Supervisor)
  end

  @impl true
  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def start_link(_nothing_interesting) do
    GenServer.start_link(__MODULE__, [%State{}], name: __MODULE__)
  end


  #######################
  # implementation
  #######################

  @impl true
  def init([state]) do
    {:ok, state}
  end

  @impl true
  def handle_call(:stop, _from, status) do
    {:stop, :normal, status}
  end

  @impl true
  def handle_call({:start_midi, device, synth, note_control, control_function}, _from, %State{midi_pid: old_pid} = state) do
    if old_pid != 0 do
      :ok = PortMidi.close(:input, old_pid)
    end
    Logger.debug("before Portmidi.open")
    case PortMidi.open(:input, device) do
      {:ok, midi_pid} ->
        Logger.debug("before PortMidi.listen") # midi_pid = #{midi_pid}")
        PortMidi.listen(midi_pid, self())
        # Logger.info("device #{device}, synth #{synth}, note_control #{note_control}")
        {:reply, {:ok, midi_pid}, %{state |
                                    note_module_id: synth,
                                    control_function: control_function,
                                    note_control: note_control,
                                    midi_pid: midi_pid}}
      {:error, reason} ->
        Logger.warning("Midi device #{device} not found because #{reason}")
        {:reply, {:error, reason}, %{state | midi_pid: 0}}
      end
  end

  @impl true
  def handle_call({:register_cc, cc_num, cc_id, cc_control}, _from, %State{cc_registry: cc_registry, midi_pid: midi_pid} = state) do
    Logger.info("cc_num #{cc_num} cc #{cc_id}, cc_control #{cc_control}")

    case midi_pid do
    0 -> {:reply, :no_midi, state}
    _pid ->
      cc_specs = Map.get(cc_registry, cc_num, [])

      {:reply, :ok,
       %{state | cc_registry: Map.put(cc_registry, cc_num, cc_specs ++ [%MidiIn.CC{cc_id: cc_id, cc_control: cc_control}])}}
    end
  end

  @impl true
  def handle_call({:register_gate, id}, _from, %State{gate_registry: gate_registry} = state) do
    gate_registry = [id|gate_registry]
    Logger.info("gate_registry: #{inspect(gate_registry)}")
    {:reply, :ok,
     %{state | gate_registry: gate_registry}}
  end

  @impl true
  def handle_call(:stop_midi, _from, %State{midi_pid: midi_pid}) do
    Logger.debug("midi_pid: #{inspect(midi_pid)}")
    if midi_pid != 0 do
      PortMidi.close(:input, midi_pid)
    end
    {:reply, :ok, %State{midi_pid: 0, gate_registry: []}}
  end

  @impl true
  def handle_info({:open_gate, id}, %State{control_function: set_control} = state) do
    set_control.(id, "gate", 1)
    Logger.info("set control #{id} gate 1")
    {:noreply, state}
  end

  @impl true
  def handle_info({_pid, messages}, state) do
    Logger.debug("#{inspect(messages)}")
    {:noreply, Enum.reduce(messages, state, fn m, acc -> process_message(m, acc) end)}
  end


  @doc """
  processes the message and returns a possibly new state
  """
  def process_message({{status, note, vel}, _timestamp}, %State{control_function: set_control,
                                                                last_note: last_note,
                                                                gate_registry: gate_registry} = state) do
    new_note = cond do
        (status >= 0x80) && (status < 0x90) ->
          Logger.warning("unexpected noteoff message")
          last_note
        (status >= 0x90) && (status < 0xA0) ->
        if state.note_module_id != 0 and vel != 0 do
          set_control.(state.note_module_id, state.note_control, note)
          Enum.each(gate_registry, fn g ->
            set_control.(g, "gate", 0)
            Logger.info("set control #{g} gate 0")
            Process.send_after(self(), {:open_gate, g}, 50)
          end)
          # Logger.info("note #{note} vel #{vel} synth #{state.note_module_id} control #{state.note_control}")
          note
        else
          last_note
        end

        (status >= 0xA0) && (status < 0xB0) ->
          Logger.warning("unexpected polyphonic touch message")
          last_note

        (status >= 0xB0) && (status < 0xC0) ->
          set_vol(state, note, vel, set_control)
          last_note

        (status >= 0xC0) && (status < 0xD0) ->
          Logger.info("pc message #{Integer.to_string(note, 16)} val #{vel} not handled")# program_change
          last_note

        (status >= 0xD0) && (status < 0xE0) ->
          set_vol(state, 2, note, set_control)
          last_note

        (status >= 0xE0) && (status < 0xF0) ->
          msb = vel
          lsb = note
          bend = (((msb <<< 7) + lsb) - 8192) / 4000.0
          if state.note_module_id != 0 do
            set_control.(state.note_module_id, state.note_control, last_note + bend)
          end
          #Logger.warn("unexpected pitch_wheel_message note #{bend}")
          last_note

        status == 0xF0 ->
          Logger.warning("unexpected sysex_message")
          last_note
    end
    %State{state | last_note: new_note}
  end

  def set_vol(state, note, vel, set_control) do
    cc_list = Map.get(state.cc_registry, note, 0)
    if cc_list == 0 do
      Logger.info("cc message #{Integer.to_string(note, 16)} val #{vel} not handled")
    else
      Enum.each(cc_list, fn %MidiIn.CC{cc_id: cc_id, cc_control: cc_control} ->
        set_control.(cc_id, cc_control, vel / 127)
      end)
    end
  end
  ###########################################################
  # test functions
  ###########################################################

  # @doc """
  # instantiate a supercollider synth and play it using midi input device.
  # def tm(synth) do
  #   MidiIn.start(0,0)
  #   id = ScClient.make_module(synth, ["amp", 0.2, "note", 55])
  #   {:ok, pid} = MidiInClient.start_midi(id, "note", &ScClient.set_control/3)
  #   MidiInClient.register_cc(2, id, "amp")
  #   pid
  # end
  # """

  ###########################################################

  def my_set_control(id, control, val) do
    case control do
      "me" -> Logger.info("id: #{id} control: #{control} val: #{val}")
      _ -> nil
    end
  end

  def tm() do
    {:ok, _pid} = MidiInClient.start_midi(1, "me", &my_set_control/3)
    MidiInClient.register_cc(2, 1, "amp")
  end

end
