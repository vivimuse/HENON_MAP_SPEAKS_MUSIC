# HENON SPEAKS MUSIC -> CONTROLLED CHAOS 
# Muse doesn't improvise. She iterates.
# Determinism wrote the score. 
# And yes, it's only my second coding project //;>

# Plato wanted an eternal form
# Muse handed him a strange attractor. // searching_the_A ;> 

println("Loading HENON SPEAKS MUSIC — A2-A5...")
flush(stdout)

const PROJECT_FOLDER = joinpath(homedir(), "Desktop", "VIVIMUSE_HENON")
const PROJECT_ROOT = abspath(expanduser(get(ENV, "HENON_PROJECT_DIR", PROJECT_FOLDER)))

module HarmonicA2
using Plots
using FFMPEG
using Printf
gr()

const PROJECT_ROOT = getfield(parentmodule(@__MODULE__), :PROJECT_ROOT)

const FPS = 24
const NOTE_COUNT = 32 
# 32 events, 3 mappings, 2 voices, 3:02 min video. 
# Oh, come on, again, Gaston Julia ? Are you playing numerology with Muse? 

const WIDTH = 1080
const HEIGHT = 1080
const SAMPLE_RATE = 44100
const NOTE = 1.75
const TAIL_DURATION = 0.0
const DURATION = NOTE_COUNT * NOTE + TAIL_DURATION
const NOTE_GAP = 0.072
const FIXED_MIDI_VELOCITY = 88

const OUTPUT_DIR = joinpath(PROJECT_ROOT, "henon_a2_a5_harmonic_render")
const FRAME_DIR = joinpath(OUTPUT_DIR, "frames")
const DEFAULT_AUDIO = joinpath(PROJECT_ROOT, "henon_a2_a5_harmonic.wav")
const VIDEO_ONLY = joinpath(OUTPUT_DIR, "henon_duet_silent.mp4")
const FINAL_VIDEO = joinpath(OUTPUT_DIR, "henon_a2_a5_harmonic.mp4")
const MIDI_FILE = joinpath(PROJECT_ROOT, "henon_a2_a5_harmonic_for_logic.mid")
const PIANO_CREDIT = "PIANO: STEINWAY / LOGIC PRO"
const AUDIO_CREDIT = "HENON MUSIC. Piano: Steinway Grand Piano, Logic Pro. 32 pairs at 1.75 seconds each; consecutive Henon iterates 10001 through 10032. The melody and harmony use authored C-major mapping rules. One common X-Y scale preserves the attractor shape. A faint complete cloud and a fixed subset of actual iterates form a steady dotted attractor; only the white cursor and active keys pulse. State coordinates and equal-tempered note frequencies are shown. Smooth marker motion is display interpolation. Balanced stereo piano with the approved soft room response. Duration 56 seconds."
const VIDEO_SCENE_ID = "henon-speaks-music-175-v1|range=A2-A5|rule=harmonic|1080x1080|24fps|56s|1344frames|pair=1.75s|gate=1.678s|step=1|opening57-50|display-margin-9-center5.98-width11.3-alpha.11-.74|counter=PAIR01-32|heading=HENON|formula=20-v2"
const VIDEO_MARKER = joinpath(OUTPUT_DIR, "video_scene.txt")

function midi_write_be(io, value::Integer, bytes::Integer)
    value >= 0 || throw(ArgumentError("MIDI integer must be nonnegative."))
    for shift in (8 * (bytes - 1)):-8:0
        write(io, UInt8((value >> shift) & 0xff))
    end
end

function midi_write_vlq(io, value::Integer)
    0 <= value <= 0x0fffffff ||
        throw(ArgumentError("MIDI variable-length value is out of range."))
    encoded = UInt8[UInt8(value & 0x7f)]
    value >>= 7
    while value > 0
        push!(encoded, UInt8((value & 0x7f) | 0x80))
        value >>= 7
    end
    write(io, reverse(encoded))
end

function midi_meta(io, kind::Integer, payload::AbstractVector{UInt8})
    write(io, UInt8[0xff, UInt8(kind)])
    midi_write_vlq(io, length(payload))
    write(io, payload)
end

function midi_track(io, data::Vector{UInt8})
    length(data) <= typemax(UInt32) ||
        throw(ArgumentError("MIDI track exceeds the file format limit."))
    write(io, codeunits("MTrk"))
    midi_write_be(io, length(data), 4)
    write(io, data)
end

function write_midi(path, voices, velocities;
                    note=NOTE, note_gap=NOTE_GAP, duration=DURATION)
    ndims(voices) == 2 && size(voices, 2) == 2 ||
        throw(ArgumentError("MIDI export expects two voice columns."))
    size(voices) == size(velocities) ||
        throw(ArgumentError("Notes and velocities must have the same shape."))
    isfinite(note) && isfinite(note_gap) && isfinite(duration) &&
        0 < note_gap < note && duration > 0 ||
        throw(ArgumentError("Invalid MIDI timing settings."))
    all(m -> m isa Integer && 0 <= m <= 127, voices) ||
        throw(ArgumentError("MIDI notes must be integers from 0 to 127."))
    all(isfinite, velocities) ||
        throw(ArgumentError("MIDI velocities must be finite."))

    ticks_per_second = 1000
    duration_ticks = round(Int, duration * ticks_per_second)
    duration_ticks <= 0x0fffffff ||
        throw(ArgumentError("MIDI duration is too long."))

    events = [Tuple{Int,Int,Vector{UInt8}}[] for _ in 1:2]
    for k in axes(voices, 1)
        onset = round(Int, (k - 1) * note * ticks_per_second)
        release = round(Int, (k * note - note_gap) * ticks_per_second)
        0 <= onset < release <= duration_ticks ||
            throw(ArgumentError("A MIDI note falls outside the duration or is shorter than 1 ms."))
        for voice in 1:2
            channel = voice - 1
            midi_note = UInt8(voices[k, voice])

            velocity = UInt8(round(Int, clamp(velocities[k, voice], 1 / 127, 1) * 127))
            push!(events[voice], (onset, 1, UInt8[0x90 + channel, midi_note, velocity]))
            push!(events[voice], (release, 0, UInt8[0x80 + channel, midi_note, 0]))
        end
    end

    open(path, "w") do io
        write(io, codeunits("MThd"))
        midi_write_be(io, 6, 4)
        midi_write_be(io, 1, 2)
        midi_write_be(io, 3, 2)
        midi_write_be(io, 1000, 2)

        tempo_track = IOBuffer()
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x03, collect(codeunits("Henon even dynamics - 32 pairs - velocity 88")))
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x51, UInt8[0x0f, 0x42, 0x40])
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x58, UInt8[4, 2, 24, 8])
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x59, UInt8[0, 0])
        midi_write_vlq(tempo_track, duration_ticks)
        midi_meta(tempo_track, 0x2f, UInt8[])
        midi_track(io, take!(tempo_track))

        for voice in 1:2
            channel = voice - 1
            track = IOBuffer()
            midi_write_vlq(track, 0)
            midi_meta(track, 0x03, collect(codeunits(("Original melody", "Diatonic harmony")[voice])))
            midi_write_vlq(track, 0)
            write(track, UInt8[0xc0 + channel, 0])
            midi_write_vlq(track, 0)
            write(track, UInt8[0xb0 + channel, 10, (42, 86)[voice]])
            midi_write_vlq(track, 0)
            write(track, UInt8[0xb0 + channel, 7, (100, 100)[voice]])

            previous_tick = 0

            sort!(events[voice]; by=event -> (event[1], event[2]))
            for (tick, _, data) in events[voice]
                midi_write_vlq(track, tick - previous_tick)
                write(track, data)
                previous_tick = tick
            end
            midi_write_vlq(track, duration_ticks - previous_tick)
            midi_meta(track, 0x2f, UInt8[])
            midi_track(io, take!(track))
        end
    end
    return path
end

const A = 1.4
const B = 0.3
const X0 = 0.1    
const Y0 = 0.0
# 10.000 iterations before the show even starts.
# Apparently, chaos also needs a rehearsal. //;>

const BURN_IN = 10000
const ATTRACTOR_POINTS = 60000
const DISPLAY_POINT_COUNT = 3000
const ORBIT_STEP = 1
const ATTRACTOR_CENTER = (5.98, 7.10)
const ATTRACTOR_WIDTH = 11.3
const ATTRACTOR_HEIGHT = 5.3
const KEYBOARD_ALPHA = 0.40
const TEXT_LEFT = 0.4
const TEXT_RIGHT = 11.6

const START_MIDI = 57
const LOW_MIDI = 45
const HIGH_MIDI = 81
const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const C_MAJOR_NOTES = [m for m in LOW_MIDI:HIGH_MIDI if mod(m, 12) in (0, 2, 4, 5, 7, 9, 11)]

const SCALE_STEP_JUMPS = [-7, -5, -3, -2, -1, 1, 2, 3, 5, 7, 9]

const HARMONY_SCALE_STEPS = [2, 4, 5, 7]
const MARKER_COLOR = "#ffffff"
const INTERVAL_NAMES = (
    "unison", "minor 2nd", "major 2nd", "minor 3rd", "major 3rd",
    "perfect 4th", "tritone", "perfect 5th", "minor 6th", "major 6th",
    "minor 7th", "major 7th", "octave"
)

midi_freq(m) = 440.0 * 2.0^((m - 69) / 12)
note_name(m) = NOTE_NAMES[mod(m, 12) + 1] * string(fld(m, 12) - 1)
interval_semitones(a, b) = abs(a - b)
function interval_name(semitones::Integer)
    0 <= semitones <= HIGH_MIDI - LOW_MIDI ||
        throw(ArgumentError("Interval outside the A2-A5 range: $semitones."))
    semitones <= 12 && return INTERVAL_NAMES[semitones + 1]
    octaves, remainder = divrem(semitones, 12)
    remainder == 0 && return "$octaves octaves"
    "$octaves oct + " * INTERVAL_NAMES[remainder + 1]
end
number_of_notes() = NOTE_COUNT
number_of_frames() = round(Int, FPS * DURATION)

function validate_settings()
    @assert FPS > 0 && SAMPLE_RATE > 0 && DURATION > 0
    @assert 0 < NOTE_GAP < NOTE
    @assert FIXED_MIDI_VELOCITY isa Integer && 1 <= FIXED_MIDI_VELOCITY <= 127
    @assert isfinite(TAIL_DURATION) && TAIL_DURATION >= 0
    @assert isapprox(DURATION, number_of_notes() * NOTE + TAIL_DURATION; atol=1e-10, rtol=0) "Use the note sequence duration plus the tail."
    @assert isapprox(FPS * DURATION, number_of_frames(); atol=1e-10, rtol=0) "Use a whole number of frames."
    @assert isapprox(FPS * NOTE, round(Int, FPS * NOTE); atol=1e-10, rtol=0) "Use a whole number of frames per note."
    @assert number_of_notes() >= 1 && ORBIT_STEP == 1
    @assert B != 0 && BURN_IN >= 1
    @assert START_MIDI in C_MAJOR_NOTES
    @assert all(d -> 1 <= d < length(C_MAJOR_NOTES) / 2, HARMONY_SCALE_STEPS)
    @assert ATTRACTOR_POINTS >= number_of_notes() * ORBIT_STEP
    @assert 1 <= DISPLAY_POINT_COUNT <= ATTRACTOR_POINTS
    @assert 0 <= KEYBOARD_ALPHA <= 1
    @assert midi_freq(HIGH_MIDI) < SAMPLE_RATE / 2
end
# LAPLACE: Give me the laws and I shall predict the universe.
# HENON: How many decimal places can you afford ?  //;>

function henon_points(n)
    xs = zeros(Float64, n)
    ys = zeros(Float64, n)
    x, y = X0, Y0
    for i in 1:n

        xn = 1.0 - A * x * x + y
        yn = B * x
        x, y = xn, yn
        isfinite(x) && isfinite(y) || error("Orbit diverged at iteration $i.")
        xs[i], ys[i] = x, y
    end
    xs, ys
end

function reflect_index(index, count)
    count >= 1 || throw(ArgumentError("count must be positive"))
    count == 1 && return 1
    period = 2 * (count - 1)
    folded = mod(index - 1, period)
    1 + min(folded, period - folded)
end

function make_sequence(xs, ys, start)
    count = number_of_notes()
    melody = zeros(Int, count)
    velocities = fill(FIXED_MIDI_VELOCITY / 127.0, count)
    indices = [start + (k - 1) * ORBIT_STEP for k in 1:count]
    previous_note_index = searchsortedfirst(C_MAJOR_NOTES, START_MIDI)

    for k in 1:count
        if k == 1
            melody[k] = START_MIDI
        else
            index, previous_index = indices[k], indices[k - 1]
            dx = xs[index] - xs[previous_index]
            dy = ys[index] - ys[previous_index]
            motion = 0.7 * dx + 0.3 * dy

            position = clamp((motion + 2.4) / 4.8, 0.0, 1.0)
            slot = clamp(floor(Int, position * length(SCALE_STEP_JUMPS)) + 1,
                         1, length(SCALE_STEP_JUMPS))
            previous_note_index = reflect_index(
                previous_note_index + SCALE_STEP_JUMPS[slot], length(C_MAJOR_NOTES))
            melody[k] = C_MAJOR_NOTES[previous_note_index]
        end
    end
    harmony = zeros(Int, count)
    harmony_velocities = fill(FIXED_MIDI_VELOCITY / 127.0, count)
    ymin, ymax = extrema(@view ys[start:end])
    for k in 1:count
        index = indices[k]
        position = clamp((ys[index] - ymin) / max(ymax - ymin, eps()), 0.0, 1.0)
        slot = min(floor(Int, position * length(HARMONY_SCALE_STEPS)) + 1,
                   length(HARMONY_SCALE_STEPS))
        distance = HARMONY_SCALE_STEPS[slot]
        lead_index = searchsortedfirst(C_MAJOR_NOTES, melody[k])

        harmony_index = lead_index - distance
        harmony_index < 1 && (harmony_index = lead_index + distance)
        harmony[k] = C_MAJOR_NOTES[harmony_index]
    end
    hcat(melody, harmony), hcat(velocities, harmony_velocities), indices
end

function make_midi(voices, velocities)
    write_midi(MIDI_FILE, voices, velocities)
    println("MIDI saved: ", abspath(MIDI_FILE))
    flush(stdout)
end

function validate_external_audio(path)
    absolute_path = abspath(expanduser(path))   

    # Absolute? Plato searched beyond appearances.
    # Aristitel searched for first principles.
    # Muse is still searching for an invariant. //;>   

    isfile(absolute_path) || error(
        "Finished WAV not found: $absolute_path\n" *
        "Save a stereo bounce from Logic Pro as henon_a2_a5_harmonic.wav in $PROJECT_ROOT " *
        "or use --audio /absolute/path/to/audio.wav.\n" *
        "Audio is not required for a preview: julia henon_speaks_music.jl --preview"
    )
    report = try
        read(`$(FFMPEG.ffprobe()) -v error -select_streams a:0 -show_entries stream=channels,sample_rate:format=format_name,duration -of default=noprint_wrappers=1 $absolute_path`, String)
    catch err
        error("Could not read WAV $absolute_path: $(sprint(showerror, err))")
    end
    fields = Dict{String, String}()
    for line in split(chomp(report), '\n')
        parts = split(line, '='; limit=2)
        length(parts) == 2 && (fields[parts[1]] = parts[2])
    end
    get(fields, "format_name", "") == "wav" || error("A stereo Logic Pro bounce in WAV format is required: $absolute_path")
    get(fields, "channels", "") == "2" || error("The WAV must contain two audio channels (stereo): $absolute_path")
    seconds = tryparse(Float64, get(fields, "duration", ""))
    !isnothing(seconds) && isfinite(seconds) && seconds > 0 || error("Could not determine WAV duration.")
    seconds + 1 / SAMPLE_RATE >= DURATION || error(@sprintf("WAV is only %.3f s; this scene requires %.3f s including a real piano tail. Supply the new bounce rather than padding silence.", seconds, DURATION))
    println("Finished Logic Pro audio: ", absolute_path)
    println(@sprintf("Audio: %.3f s; video: %.3f s. The first MIDI note must start at 0 s.", seconds, DURATION))
    flush(stdout)
    absolute_path
end

function prepare_scene()
    validate_settings()
    first_index = BURN_IN + 1
    last_index = BURN_IN + ATTRACTOR_POINTS
    xs, ys = henon_points(last_index)
    voices, velocities, indices = make_sequence(xs, ys, first_index)
    transform = attractor_transform(xs, ys, first_index, last_index)
    display_indices = round.(Int, range(1, length(transform.cloud_x); length=DISPLAY_POINT_COUNT))
    (; xs, ys, voices, velocities, indices, first_index, last_index, transform, display_indices)
end

function render_scene_frame(path, scene, frame)
    1 <= frame <= number_of_frames() || throw(ArgumentError("Frame outside the range 1:$(number_of_frames())."))
    draw_frame(path, scene, frame)
end

function marker_position(xs, ys, indices, time)
    note_index = clamp(floor(Int, time / NOTE) + 1, 1, length(indices))
    orbit_index = indices[note_index]
    next_index = indices[min(note_index + 1, length(indices))]
    phase = clamp((time - (note_index - 1) * NOTE) / NOTE, 0.0, 1.0)

    eased = phase^3 * (10.0 + phase * (-15.0 + 6.0 * phase))
    current_x = (1.0 - eased) * xs[orbit_index] + eased * xs[next_index]
    current_y = (1.0 - eased) * ys[orbit_index] + eased * ys[next_index]
    current_x, current_y, note_index, orbit_index
end

function attractor_transform(xs, ys, first_index, last_index)
    xmin, xmax = extrema(@view xs[first_index:last_index])
    ymin, ymax = extrema(@view ys[first_index:last_index])

    scale = min(ATTRACTOR_WIDTH / (xmax - xmin), ATTRACTOR_HEIGHT / (ymax - ymin))
    scale_x = scale_y = scale
    xmid, ymid = (xmin + xmax) / 2, (ymin + ymax) / 2
    cloud_x = ATTRACTOR_CENTER[1] .+ scale_x .* (@view(xs[first_index:last_index]) .- xmid)
    cloud_y = ATTRACTOR_CENTER[2] .+ scale_y .* (@view(ys[first_index:last_index]) .- ymid)
    (scale_x=scale_x, scale_y=scale_y, xmid=xmid, ymid=ymid, cloud_x=cloud_x, cloud_y=cloud_y)
end

screen_x(x, transform) = ATTRACTOR_CENTER[1] + transform.scale_x * (x - transform.xmid)
screen_y(y, transform) = ATTRACTOR_CENTER[2] + transform.scale_y * (y - transform.ymid)

function transition_geometry(scene, time)
    current_x, current_y, note_index, orbit_index =
        marker_position(scene.xs, scene.ys, scene.indices, time)
    transform = scene.transform
    state = (screen_x(scene.xs[orbit_index], transform), screen_y(scene.ys[orbit_index], transform))
    cursor = (screen_x(current_x, transform), screen_y(current_y, transform))
    target_index = note_index < length(scene.indices) ? scene.indices[note_index + 1] : nothing
    target = isnothing(target_index) ? nothing :
        (screen_x(scene.xs[target_index], transform), screen_y(scene.ys[target_index], transform))
    (; current_x, current_y, note_index, orbit_index, state, cursor, target_index, target)
end

 # 88 keys represent the maximum range of musically useful sounds that the human ear can fully perceive.

function draw_keyboard(p, notes, note_time=0.0)
    left_edge, right_edge = TEXT_LEFT, TEXT_RIGHT
    bottom, top = 1.10, 2.45
    key_width = (right_edge - left_edge) / length(C_MAJOR_NOTES)
    pulse = exp(-max(0.0, note_time) / 0.35)

    for (key_index, midi_note) in enumerate(C_MAJOR_NOTES)
        any(==(midi_note), notes) || continue
        left = left_edge + (key_index - 1) * key_width
        right = left + key_width
        for (padding, opacity) in ((0.090, 0.055), (0.055, 0.095), (0.025, 0.170))
            plot!(p, Shape([left-padding, right+padding, right+padding, left-padding],
                           [bottom-padding, bottom-padding, top+padding, top+padding]),
                  fillcolor="#ffffff", fillalpha=opacity * (0.75 + 0.25 * pulse),
                  linewidth=0)
        end
    end
    for (key_index, midi_note) in enumerate(C_MAJOR_NOTES)
        left = left_edge + (key_index - 1) * key_width
        right = left + key_width
        active = any(==(midi_note), notes)
        if active

            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#000000", fillalpha=1.0, linewidth=0)
            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#ffffff", fillalpha=0.88 + 0.08 * pulse,
                  linecolor="#ffffff", linealpha=0.90 + 0.10 * pulse,
                  linewidth=0.85 + 0.15 * pulse)
        else
            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#eeeeee", fillalpha=KEYBOARD_ALPHA,
                  linecolor="#a0a0a0", linealpha=0.30, linewidth=0.6)
        end
        label = mod(midi_note, 12) == 0 ? note_name(midi_note) : NOTE_NAMES[mod(midi_note, 12)+1]
        if active

            outline = 0.009
            for (dx, dy) in ((-outline, -outline), (0.0, -outline), (outline, -outline),
                             (-outline, 0.0), (outline, 0.0),
                             (-outline, outline), (0.0, outline), (outline, outline))
                annotate!(p, (left + right) / 2 + dx, bottom + 0.14 + dy,
                          text(label, 9, "#666666", :center))
            end
        end
        annotate!(p, (left + right) / 2, bottom + 0.14,
                  text(label, 9, "#ffffff", :center))
    end
    for midi_note in LOW_MIDI:HIGH_MIDI
        mod(midi_note, 12) in (1, 3, 6, 8, 10) || continue
        boundary = left_edge + searchsortedlast(C_MAJOR_NOTES, midi_note) * key_width
        left, right = boundary - 0.29 * key_width, boundary + 0.29 * key_width
        plot!(p, Shape([left, right, right, left], [bottom + 0.38*(top-bottom), bottom + 0.38*(top-bottom), top, top]),
              fillcolor="#000000", fillalpha=0.90, linewidth=0)
    end
end

function draw_frame(path, scene, frame)
    foreground, muted = "#ffffff", "#ffffff"
    time = (frame - 1) / FPS
    motion = transition_geometry(scene, time)
    current_x, current_y = motion.current_x, motion.current_y
    note_index, orbit_index = motion.note_index, motion.orbit_index
    notes = Tuple(scene.voices[note_index, :])
    semitones = interval_semitones(notes...)
    note_time = time - (note_index - 1) * NOTE
    pulse = maximum(@view scene.velocities[note_index, :]) * exp(-note_time / 0.22)
    transform = scene.transform
    p = plot(xlims=(0, 12), ylims=(0, 12), widen=false, size=(WIDTH, HEIGHT),
             aspect_ratio=:equal, axis=false, grid=false, legend=false,
             background_color="#000000", foreground_color=foreground,
             fontfamily="Helvetica", margin=-9 * Plots.mm)

    scatter!(p, transform.cloud_x, transform.cloud_y,
             markersize=0.48, markercolor="#dddddd", markeralpha=0.11,
             markerstrokewidth=0)

    scatter!(p, transform.cloud_x[scene.display_indices], transform.cloud_y[scene.display_indices],
             markersize=0.88, markercolor="#eeeeee", markeralpha=0.74,
             markerstrokewidth=0)

    angles = range(0.0, 2pi; length=33)
    plot!(p, motion.state[1] .+ 0.055 .* cos.(angles),
             motion.state[2] .+ 0.055 .* sin.(angles),
          color="#ffffff", linealpha=0.75, linewidth=1.0)

    outer_radius, inner_radius = 28 + 4 * pulse, 12 + 1.5 * pulse
    sigma = 6.5 + 0.7 * pulse
    edge = exp(-0.5 * ((outer_radius - inner_radius) / sigma)^2)
    previous_opacity = 0.0
    for radius in range(outer_radius, inner_radius; length=16)
        target_opacity = (0.30 + 0.06 * pulse) *
            (exp(-0.5 * ((radius - inner_radius) / sigma)^2) - edge) / (1.0 - edge)
        opacity = clamp((target_opacity - previous_opacity) / (1.0 - previous_opacity), 0.0, 1.0)
        previous_opacity = target_opacity
        opacity <= 1e-6 && continue
        scatter!(p, [screen_x(current_x, transform)], [screen_y(current_y, transform)],
                 markersize=radius, markercolor=MARKER_COLOR,
                 markerstrokewidth=0, markeralpha=opacity)
    end
    scatter!(p, [screen_x(current_x, transform)], [screen_y(current_y, transform)],
             markersize=10.5 + 1.5 * pulse, markercolor=MARKER_COLOR,
             markerstrokecolor=MARKER_COLOR, markerstrokewidth=1.4,
             markeralpha=1.0, markerstrokealpha=1.0)

    annotate!(p, TEXT_LEFT, 11.30, text("HENON", 23, foreground, :left))
    annotate!(p, TEXT_RIGHT, 11.30,
              text(@sprintf("xₙ₊₁ = 1 − %.1fxₙ² + yₙ;    yₙ₊₁ = %.1fxₙ", A, B),
                   20, foreground, :right))
    annotate!(p, TEXT_LEFT, 10.82,
              text("C MAJOR  ·  TWO VOICES  ·  A2–A5", 9, foreground, :left))
    annotate!(p, TEXT_LEFT, 10.42,
              text(@sprintf("PAIR %02d/%02d", note_index, NOTE_COUNT), 9, foreground, :left))
    annotate!(p, TEXT_RIGHT, 10.82,
              text("ONE ITERATION → ONE NOTE PAIR", 9, foreground, :right))

    annotate!(p, TEXT_LEFT, 3.68,
              text(@sprintf("STATE n = %d", orbit_index), 10, foreground, :left))
    annotate!(p, TEXT_LEFT, 3.20,
              text(@sprintf("x = %+.5f", scene.xs[orbit_index]), 14, foreground, :left))
    annotate!(p, TEXT_LEFT, 2.78,
              text(@sprintf("y = %+.5f", scene.ys[orbit_index]), 14, foreground, :left))
    annotate!(p, TEXT_RIGHT, 4.02,
              text(uppercase(interval_name(semitones)) * @sprintf(" · %d st", semitones),
                   17, foreground, :right))
    for (voice, anchor) in enumerate((8.4, TEXT_RIGHT))
        annotate!(p, anchor, 3.48,
                  text(note_name(notes[voice]), 26, foreground, :right))
        annotate!(p, anchor, 2.92,
                  text(@sprintf("%.2f Hz", midi_freq(notes[voice])), 11, foreground, :right))
    end
    keyboard_notes = note_time < NOTE - NOTE_GAP ? notes : ()
    draw_keyboard(p, keyboard_notes, note_time)
    annotate!(p, 6.0, 0.58,
              text("RING: COMPUTED STATE  ·  POINT: VISUAL INTERPOLATION", 8, foreground, :center))
    savefig(p, path)
    return p
end

function make_video_only()

    mkpath(OUTPUT_DIR)
    for frame in 1:number_of_frames()
        path = joinpath(FRAME_DIR, @sprintf("frame_%05d.png", frame))
        isfile(path) || error("Missing frame $frame: $path")
    end
    isfile(VIDEO_MARKER) && rm(VIDEO_MARKER)
    pattern = joinpath(FRAME_DIR, "frame_%05d.png")
    fade_out_start = max(0, DURATION - 0.8)

    fades = "pad=$WIDTH:$HEIGHT:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=$FPS,fade=t=out:st=$fade_out_start:d=0.8"
    frames = number_of_frames()
    FFMPEG.ffmpeg_exe(`-hide_banner -y -framerate $FPS -start_number 1 -i $pattern -frames:v $frames -vf $fades -c:v libx264 -profile:v high -level:v 4.0 -preset medium -tune animation -crf 14 -maxrate 8M -bufsize 16M -pix_fmt yuv420p -movflags +faststart $VIDEO_ONLY`)
    write(VIDEO_MARKER, VIDEO_SCENE_ID)
end

function validate_scene_video()
    isfile(VIDEO_ONLY) && isfile(VIDEO_MARKER) && read(VIDEO_MARKER, String) == VIDEO_SCENE_ID ||
        error("No finished video for this Steinway scene version. Run the full render first. " *
              "Other scene versions cannot be used for this remux.")
    VIDEO_ONLY
end

function add_audio(; audio_path=DEFAULT_AUDIO)
    source = validate_external_audio(audio_path)
    validate_scene_video()
    fade_start = max(0, DURATION - 0.8)
    frames = number_of_frames()

    audio_filter = "asetpts=PTS-STARTPTS,apad,atrim=duration=$DURATION,afade=t=out:st=$fade_start:d=0.8"
    FFMPEG.ffmpeg_exe(`-hide_banner -y -i $VIDEO_ONLY -i $source -map 0:v:0 -map 1:a:0 -map_metadata -1 -map_chapters -1 -c:v copy -frames:v $frames -af $audio_filter -c:a aac -profile:a aac_low -b:a 256k -ar $SAMPLE_RATE -ac 2 -t $DURATION -movflags +faststart -metadata comment=$AUDIO_CREDIT $FINAL_VIDEO`)
    FINAL_VIDEO
end

end

module DirectA2
using Plots
using FFMPEG
using Printf
gr()

const PROJECT_ROOT = getfield(parentmodule(@__MODULE__), :PROJECT_ROOT)

const FPS = 24
const NOTE_COUNT = 32
const WIDTH = 1080
const HEIGHT = 1080
const SAMPLE_RATE = 44100

const NOTE = 1.75
const TAIL_DURATION = 0.0
const DURATION = NOTE_COUNT * NOTE + TAIL_DURATION
const NOTE_GAP = 0.072
const FIXED_MIDI_VELOCITY = 88

const OUTPUT_DIR = joinpath(PROJECT_ROOT, "henon_a2_a5_direct_render")
const FRAME_DIR = joinpath(OUTPUT_DIR, "frames")
const DEFAULT_AUDIO = joinpath(PROJECT_ROOT, "henon_a2_a5_direct.wav")
const VIDEO_ONLY = joinpath(OUTPUT_DIR, "henon_duet_silent.mp4")
const FINAL_VIDEO = joinpath(OUTPUT_DIR, "henon_a2_a5_direct.mp4")
const MIDI_FILE = joinpath(PROJECT_ROOT, "henon_a2_a5_direct_for_logic.mid")
const PIANO_CREDIT = "PIANO: STEINWAY / LOGIC PRO"
const AUDIO_CREDIT = "HENON MUSIC. Steinway Grand Piano, Logic Pro. Direct coordinate sonification: x selects voice 1 and y selects voice 2 from all 22 C-major notes in A2-A5. The first pair is the supplied A3/D3 seed; later pairs are mapped directly from current x and y with no interval menu, melodic jump menu or voice ordering. The coordinates remain coupled by the Henon map. 32 pairs from consecutive iterates, 1.75 seconds each, 56 seconds total. The dotted cloud uses actual computed states; smooth cursor motion is visual interpolation."
const VIDEO_SCENE_ID = "henon-speaks-music-175-v1|range=A2-A5|rule=direct|1080x1080|24fps|56s|1344frames|pair=1.75s|gate=1.678s|step=1|opening57-50|display-margin-9-center5.98-width11.3-alpha.11-.74|counter=PAIR01-32|heading=HENON|formula=20-v2"
const VIDEO_MARKER = joinpath(OUTPUT_DIR, "video_scene.txt")

function midi_write_be(io, value::Integer, bytes::Integer)
    value >= 0 || throw(ArgumentError("MIDI integer must be nonnegative."))
    for shift in (8 * (bytes - 1)):-8:0
        write(io, UInt8((value >> shift) & 0xff))
    end
end

function midi_write_vlq(io, value::Integer)
    0 <= value <= 0x0fffffff ||
        throw(ArgumentError("MIDI variable-length value is out of range."))
    encoded = UInt8[UInt8(value & 0x7f)]
    value >>= 7
    while value > 0
        push!(encoded, UInt8((value & 0x7f) | 0x80))
        value >>= 7
    end
    write(io, reverse(encoded))
end

function midi_meta(io, kind::Integer, payload::AbstractVector{UInt8})
    write(io, UInt8[0xff, UInt8(kind)])
    midi_write_vlq(io, length(payload))
    write(io, payload)
end

function midi_track(io, data::Vector{UInt8})
    length(data) <= typemax(UInt32) ||
        throw(ArgumentError("MIDI track exceeds the file format limit."))
    write(io, codeunits("MTrk"))
    midi_write_be(io, length(data), 4)
    write(io, data)
end

function write_midi(path, voices, velocities;
                    note=NOTE, note_gap=NOTE_GAP, duration=DURATION)
    ndims(voices) == 2 && size(voices, 2) == 2 ||
        throw(ArgumentError("MIDI export expects two voice columns."))
    size(voices) == size(velocities) ||
        throw(ArgumentError("Notes and velocities must have the same shape."))
    isfinite(note) && isfinite(note_gap) && isfinite(duration) &&
        0 < note_gap < note && duration > 0 ||
        throw(ArgumentError("Invalid MIDI timing settings."))
    all(m -> m isa Integer && 0 <= m <= 127, voices) ||
        throw(ArgumentError("MIDI notes must be integers from 0 to 127."))
    all(isfinite, velocities) ||
        throw(ArgumentError("MIDI velocities must be finite."))

    ticks_per_second = 1000
    duration_ticks = round(Int, duration * ticks_per_second)
    duration_ticks <= 0x0fffffff ||
        throw(ArgumentError("MIDI duration is too long."))

    events = [Tuple{Int,Int,Vector{UInt8}}[] for _ in 1:2]
    for k in axes(voices, 1)
        onset = round(Int, (k - 1) * note * ticks_per_second)
        release = round(Int, (k * note - note_gap) * ticks_per_second)
        0 <= onset < release <= duration_ticks ||
            throw(ArgumentError("A MIDI note falls outside the duration or is shorter than 1 ms."))
        for voice in 1:2
            channel = voice - 1
            midi_note = UInt8(voices[k, voice])

            velocity = UInt8(round(Int, clamp(velocities[k, voice], 1 / 127, 1) * 127))
            push!(events[voice], (onset, 1, UInt8[0x90 + channel, midi_note, velocity]))
            push!(events[voice], (release, 0, UInt8[0x80 + channel, midi_note, 0]))
        end
    end

    open(path, "w") do io
        write(io, codeunits("MThd"))
        midi_write_be(io, 6, 4)
        midi_write_be(io, 1, 2)
        midi_write_be(io, 3, 2)
        midi_write_be(io, 1000, 2)

        tempo_track = IOBuffer()
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x03, collect(codeunits("Henon direct XY - no interval menu - 32 pairs")))
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x51, UInt8[0x0f, 0x42, 0x40])
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x58, UInt8[4, 2, 24, 8])
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x59, UInt8[0, 0])
        midi_write_vlq(tempo_track, duration_ticks)
        midi_meta(tempo_track, 0x2f, UInt8[])
        midi_track(io, take!(tempo_track))

        for voice in 1:2
            channel = voice - 1
            track = IOBuffer()
            midi_write_vlq(track, 0)
            midi_meta(track, 0x03, collect(codeunits(("Voice 1 - X coordinate", "Voice 2 - Y coordinate")[voice])))
            midi_write_vlq(track, 0)
            write(track, UInt8[0xc0 + channel, 0])
            midi_write_vlq(track, 0)
            write(track, UInt8[0xb0 + channel, 10, (42, 86)[voice]])
            midi_write_vlq(track, 0)
            write(track, UInt8[0xb0 + channel, 7, (100, 100)[voice]])

            previous_tick = 0

            sort!(events[voice]; by=event -> (event[1], event[2]))
            for (tick, _, data) in events[voice]
                midi_write_vlq(track, tick - previous_tick)
                write(track, data)
                previous_tick = tick
            end
            midi_write_vlq(track, duration_ticks - previous_tick)
            midi_meta(track, 0x2f, UInt8[])
            midi_track(io, take!(track))
        end
    end
    return path
end

const A = 1.4
const B = 0.3
const X0 = 0.1
const Y0 = 0.0
const BURN_IN = 10000
const ATTRACTOR_POINTS = 60000

const DISPLAY_POINT_COUNT = 3000
const ORBIT_STEP = 1

const ATTRACTOR_CENTER = (5.98, 7.10)
const ATTRACTOR_WIDTH = 11.3
const ATTRACTOR_HEIGHT = 5.3
const KEYBOARD_ALPHA = 0.40
const TEXT_LEFT = 0.4
const TEXT_RIGHT = 11.6

 # Note names (Do, Re, Mi...) were created in the 11th century by Guido d'Arezzo.
 # They are taken from the first syllables of each line in a Latin hymn to St. John:
 # UT (later DO) - Ut queant laxis
 # RE             - Resonare fibris
 # MI             - Mira gestorum
 # FA             - Famuli tuorum
 # SOL            - Solve polluti
 # LA             - Labii reatum
 # SI             - Formed later from the initials of "Sancte Ioannes" //;>

const INITIAL_NOTES = (57, 50)
const LOW_MIDI = 45
const HIGH_MIDI = 81
const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const C_MAJOR_NOTES = [m for m in LOW_MIDI:HIGH_MIDI if mod(m, 12) in (0, 2, 4, 5, 7, 9, 11)]

const MARKER_COLOR = "#ffffff"
const INTERVAL_NAMES = (
    "unison", "minor 2nd", "major 2nd", "minor 3rd", "major 3rd",
    "perfect 4th", "tritone", "perfect 5th", "minor 6th", "major 6th",
    "minor 7th", "major 7th", "octave"
)

midi_freq(m) = 440.0 * 2.0^((m - 69) / 12)
note_name(m) = NOTE_NAMES[mod(m, 12) + 1] * string(fld(m, 12) - 1)
interval_semitones(a, b) = abs(a - b)
function interval_name(semitones::Integer)
    0 <= semitones <= HIGH_MIDI - LOW_MIDI ||
        throw(ArgumentError("Interval outside the A2-A5 range: $semitones."))
    semitones <= 12 && return INTERVAL_NAMES[semitones + 1]
    octaves, remainder = divrem(semitones, 12)
    remainder == 0 && return "$octaves octaves"
    "$octaves oct + " * INTERVAL_NAMES[remainder + 1]
end
number_of_notes() = NOTE_COUNT
number_of_frames() = round(Int, FPS * DURATION)

function validate_settings()
    @assert FPS > 0 && SAMPLE_RATE > 0 && DURATION > 0
    @assert 0 < NOTE_GAP < NOTE
    @assert FIXED_MIDI_VELOCITY isa Integer && 1 <= FIXED_MIDI_VELOCITY <= 127
    @assert isfinite(TAIL_DURATION) && TAIL_DURATION >= 0
    @assert isapprox(DURATION, number_of_notes() * NOTE + TAIL_DURATION; atol=1e-10, rtol=0) "Use the note sequence duration plus the tail."
    @assert isapprox(FPS * DURATION, number_of_frames(); atol=1e-10, rtol=0) "Use a whole number of frames."
    @assert isapprox(FPS * NOTE, round(Int, FPS * NOTE); atol=1e-10, rtol=0) "Use a whole number of frames per note."
    @assert number_of_notes() >= 1 && ORBIT_STEP == 1
    @assert B != 0 && BURN_IN >= 1
    @assert all(note -> note in C_MAJOR_NOTES, INITIAL_NOTES)
    @assert ATTRACTOR_POINTS >= number_of_notes() * ORBIT_STEP
    @assert 1 <= DISPLAY_POINT_COUNT <= ATTRACTOR_POINTS
    @assert 0 <= KEYBOARD_ALPHA <= 1
    @assert midi_freq(HIGH_MIDI) < SAMPLE_RATE / 2
end

function henon_points(n)
    xs = zeros(Float64, n)
    ys = zeros(Float64, n)
    x, y = X0, Y0
    for i in 1:n

        xn = 1.0 - A * x * x + y
        yn = B * x
        x, y = xn, yn
        isfinite(x) && isfinite(y) || error("Orbit diverged at iteration $i.")
        xs[i], ys[i] = x, y
    end
    xs, ys
end

function coordinate_note(value, minimum, maximum)
    maximum > minimum || throw(ArgumentError("Coordinate reference range must be positive."))
    position = clamp((value - minimum) / (maximum - minimum), 0.0, 1.0)
    index = min(floor(Int, position * length(C_MAJOR_NOTES)) + 1, length(C_MAJOR_NOTES))
    C_MAJOR_NOTES[index]
end

function make_sequence(xs, ys, start)
    count = number_of_notes()
    indices = [start + (k - 1) * ORBIT_STEP for k in 1:count]
    xmin, xmax = extrema(@view xs[start:end])
    ymin, ymax = extrema(@view ys[start:end])
    voices = zeros(Int, count, 2)
    for k in 1:count
        n = indices[k]
        if k == 1
            voices[k, 1], voices[k, 2] = INITIAL_NOTES
        else
            voices[k, 1] = coordinate_note(xs[n], xmin, xmax)
            voices[k, 2] = coordinate_note(ys[n], ymin, ymax)
        end
    end
    velocities = fill(FIXED_MIDI_VELOCITY / 127.0, count, 2)
    voices, velocities, indices
end

function make_midi(voices, velocities)
    write_midi(MIDI_FILE, voices, velocities)
    println("MIDI saved: ", abspath(MIDI_FILE))
    flush(stdout)
end

function validate_external_audio(path)
    absolute_path = abspath(expanduser(path))
    isfile(absolute_path) || error(
        "Finished WAV not found: $absolute_path\n" *
        "Save a stereo bounce from Logic Pro as henon_a2_a5_direct.wav in $PROJECT_ROOT " *
        "or use --audio /absolute/path/to/audio.wav.\n" *
        "Audio is not required for a preview: julia henon_speaks_music.jl --preview"
    )
    report = try
        read(`$(FFMPEG.ffprobe()) -v error -select_streams a:0 -show_entries stream=channels,sample_rate:format=format_name,duration -of default=noprint_wrappers=1 $absolute_path`, String)
    catch err
        error("Could not read WAV $absolute_path: $(sprint(showerror, err))")
    end
    fields = Dict{String, String}()
    for line in split(chomp(report), '\n')
        parts = split(line, '='; limit=2)
        length(parts) == 2 && (fields[parts[1]] = parts[2])
    end
    get(fields, "format_name", "") == "wav" || error("A stereo Logic Pro bounce in WAV format is required: $absolute_path")
    get(fields, "channels", "") == "2" || error("The WAV must contain two audio channels (stereo): $absolute_path")
    seconds = tryparse(Float64, get(fields, "duration", ""))
    !isnothing(seconds) && isfinite(seconds) && seconds > 0 || error("Could not determine WAV duration.")
    seconds + 1 / SAMPLE_RATE >= DURATION || error(@sprintf("WAV is only %.3f s; this scene requires %.3f s including a real piano tail. Supply the new bounce rather than padding silence.", seconds, DURATION))
    println("Finished Logic Pro audio: ", absolute_path)
    println(@sprintf("Audio: %.3f s; video: %.3f s. The first MIDI note must start at 0 s.", seconds, DURATION))
    flush(stdout)
    absolute_path
end

function prepare_scene()
    validate_settings()
    first_index = BURN_IN + 1
    last_index = BURN_IN + ATTRACTOR_POINTS
    xs, ys = henon_points(last_index)
    voices, velocities, indices = make_sequence(xs, ys, first_index)
    transform = attractor_transform(xs, ys, first_index, last_index)
    display_indices = round.(Int, range(1, length(transform.cloud_x); length=DISPLAY_POINT_COUNT))
    (; xs, ys, voices, velocities, indices, first_index, last_index, transform, display_indices)
end

function render_scene_frame(path, scene, frame)
    1 <= frame <= number_of_frames() || throw(ArgumentError("Frame outside the range 1:$(number_of_frames())."))
    draw_frame(path, scene, frame)
end

function marker_position(xs, ys, indices, time)
    note_index = clamp(floor(Int, time / NOTE) + 1, 1, length(indices))
    orbit_index = indices[note_index]
    next_index = indices[min(note_index + 1, length(indices))]
    phase = clamp((time - (note_index - 1) * NOTE) / NOTE, 0.0, 1.0)

    eased = phase^3 * (10.0 + phase * (-15.0 + 6.0 * phase))
    current_x = (1.0 - eased) * xs[orbit_index] + eased * xs[next_index]
    current_y = (1.0 - eased) * ys[orbit_index] + eased * ys[next_index]
    current_x, current_y, note_index, orbit_index
end

# NEUROBIOLOGICAL BRIDGE:
# In computational neuroscience, biological brains are modeled as non-linear 
# dynamical networks that process sensory noise by converging into "attractor states".
# While structures like the hippocampus use point/ring attractors for memory, 
# chaotic (strange) attractors are hypothesized to underly rapid sensory recognition, 
# preventing the network from locking into rigid states. //;>
function attractor_transform(xs, ys, first_index, last_index)
    xmin, xmax = extrema(@view xs[first_index:last_index])
    ymin, ymax = extrema(@view ys[first_index:last_index])

    scale = min(ATTRACTOR_WIDTH / (xmax - xmin), ATTRACTOR_HEIGHT / (ymax - ymin))
    scale_x = scale_y = scale
    xmid, ymid = (xmin + xmax) / 2, (ymin + ymax) / 2
    cloud_x = ATTRACTOR_CENTER[1] .+ scale_x .* (@view(xs[first_index:last_index]) .- xmid)
    cloud_y = ATTRACTOR_CENTER[2] .+ scale_y .* (@view(ys[first_index:last_index]) .- ymid)
    (scale_x=scale_x, scale_y=scale_y, xmid=xmid, ymid=ymid, cloud_x=cloud_x, cloud_y=cloud_y)
end

screen_x(x, transform) = ATTRACTOR_CENTER[1] + transform.scale_x * (x - transform.xmid)
screen_y(y, transform) = ATTRACTOR_CENTER[2] + transform.scale_y * (y - transform.ymid)

function transition_geometry(scene, time)
    current_x, current_y, note_index, orbit_index =
        marker_position(scene.xs, scene.ys, scene.indices, time)
    transform = scene.transform
    state = (screen_x(scene.xs[orbit_index], transform), screen_y(scene.ys[orbit_index], transform))
    cursor = (screen_x(current_x, transform), screen_y(current_y, transform))
    target_index = note_index < length(scene.indices) ? scene.indices[note_index + 1] : nothing
    target = isnothing(target_index) ? nothing :
        (screen_x(scene.xs[target_index], transform), screen_y(scene.ys[target_index], transform))
    (; current_x, current_y, note_index, orbit_index, state, cursor, target_index, target)
end

function draw_keyboard(p, notes, note_time=0.0)
    left_edge, right_edge = TEXT_LEFT, TEXT_RIGHT
    bottom, top = 1.10, 2.45
    key_width = (right_edge - left_edge) / length(C_MAJOR_NOTES)
    pulse = exp(-max(0.0, note_time) / 0.35)

    for (key_index, midi_note) in enumerate(C_MAJOR_NOTES)
        any(==(midi_note), notes) || continue
        left = left_edge + (key_index - 1) * key_width
        right = left + key_width
        for (padding, opacity) in ((0.090, 0.055), (0.055, 0.095), (0.025, 0.170))
            plot!(p, Shape([left-padding, right+padding, right+padding, left-padding],
                           [bottom-padding, bottom-padding, top+padding, top+padding]),
                  fillcolor="#ffffff", fillalpha=opacity * (0.75 + 0.25 * pulse),
                  linewidth=0)
        end
    end
    for (key_index, midi_note) in enumerate(C_MAJOR_NOTES)
        left = left_edge + (key_index - 1) * key_width
        right = left + key_width
        active = any(==(midi_note), notes)
        if active

            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#000000", fillalpha=1.0, linewidth=0)
            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#ffffff", fillalpha=0.88 + 0.08 * pulse,
                  linecolor="#ffffff", linealpha=0.90 + 0.10 * pulse,
                  linewidth=0.85 + 0.15 * pulse)
        else
            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#eeeeee", fillalpha=KEYBOARD_ALPHA,
                  linecolor="#a0a0a0", linealpha=0.30, linewidth=0.6)
        end
        label = mod(midi_note, 12) == 0 ? note_name(midi_note) : NOTE_NAMES[mod(midi_note, 12)+1]
        if active

            outline = 0.009
            for (dx, dy) in ((-outline, -outline), (0.0, -outline), (outline, -outline),
                             (-outline, 0.0), (outline, 0.0),
                             (-outline, outline), (0.0, outline), (outline, outline))
                annotate!(p, (left + right) / 2 + dx, bottom + 0.14 + dy,
                          text(label, 9, "#666666", :center))
            end
        end
        annotate!(p, (left + right) / 2, bottom + 0.14,
                  text(label, 9, "#ffffff", :center))
    end
    for midi_note in LOW_MIDI:HIGH_MIDI
        mod(midi_note, 12) in (1, 3, 6, 8, 10) || continue
        boundary = left_edge + searchsortedlast(C_MAJOR_NOTES, midi_note) * key_width
        left, right = boundary - 0.29 * key_width, boundary + 0.29 * key_width
        plot!(p, Shape([left, right, right, left], [bottom + 0.38*(top-bottom), bottom + 0.38*(top-bottom), top, top]),
              fillcolor="#000000", fillalpha=0.90, linewidth=0)
    end
end

# PLATO - REPUBLIC VII, 527b:
# "Geometry is knowledge of the eternally existent,
#  and of the things that always are, and never come to be nor pass away."

function draw_frame(path, scene, frame)
    foreground, muted = "#ffffff", "#ffffff"
    time = (frame - 1) / FPS
    motion = transition_geometry(scene, time)
    current_x, current_y = motion.current_x, motion.current_y
    note_index, orbit_index = motion.note_index, motion.orbit_index
    notes = Tuple(scene.voices[note_index, :])
    semitones = interval_semitones(notes...)
    note_time = time - (note_index - 1) * NOTE
    pulse = maximum(@view scene.velocities[note_index, :]) * exp(-note_time / 0.22)
    transform = scene.transform
    p = plot(xlims=(0, 12), ylims=(0, 12), widen=false, size=(WIDTH, HEIGHT),
             aspect_ratio=:equal, axis=false, grid=false, legend=false,
             background_color="#000000", foreground_color=foreground,
             fontfamily="Helvetica", margin=-9 * Plots.mm)

    scatter!(p, transform.cloud_x, transform.cloud_y,
             markersize=0.48, markercolor="#dddddd", markeralpha=0.11,
             markerstrokewidth=0)

    scatter!(p, transform.cloud_x[scene.display_indices], transform.cloud_y[scene.display_indices],
             markersize=0.88, markercolor="#eeeeee", markeralpha=0.74,
             markerstrokewidth=0)

    angles = range(0.0, 2pi; length=33)
    plot!(p, motion.state[1] .+ 0.055 .* cos.(angles),
             motion.state[2] .+ 0.055 .* sin.(angles),
          color="#ffffff", linealpha=0.75, linewidth=1.0)

    outer_radius, inner_radius = 28 + 4 * pulse, 12 + 1.5 * pulse
    sigma = 6.5 + 0.7 * pulse
    edge = exp(-0.5 * ((outer_radius - inner_radius) / sigma)^2)
    previous_opacity = 0.0
    for radius in range(outer_radius, inner_radius; length=16)
        target_opacity = (0.30 + 0.06 * pulse) *
            (exp(-0.5 * ((radius - inner_radius) / sigma)^2) - edge) / (1.0 - edge)
        opacity = clamp((target_opacity - previous_opacity) / (1.0 - previous_opacity), 0.0, 1.0)
        previous_opacity = target_opacity
        opacity <= 1e-6 && continue
        scatter!(p, [screen_x(current_x, transform)], [screen_y(current_y, transform)],
                 markersize=radius, markercolor=MARKER_COLOR,
                 markerstrokewidth=0, markeralpha=opacity)
    end
    scatter!(p, [screen_x(current_x, transform)], [screen_y(current_y, transform)],
             markersize=10.5 + 1.5 * pulse, markercolor=MARKER_COLOR,
             markerstrokecolor=MARKER_COLOR, markerstrokewidth=1.4,
             markeralpha=1.0, markerstrokealpha=1.0)

    annotate!(p, TEXT_LEFT, 11.30, text("HENON", 23, foreground, :left))
    annotate!(p, TEXT_RIGHT, 11.30,
              text(@sprintf("xₙ₊₁ = 1 − %.1fxₙ² + yₙ;    yₙ₊₁ = %.1fxₙ", A, B),
                   20, foreground, :right))
    annotate!(p, TEXT_LEFT, 10.82,
              text("C MAJOR  ·  TWO VOICES  ·  A2–A5", 9, foreground, :left))
    annotate!(p, TEXT_LEFT, 10.42,
              text(@sprintf("PAIR %02d/%02d", note_index, NOTE_COUNT), 9, foreground, :left))
    annotate!(p, TEXT_RIGHT, 10.82,
              text(note_index == 1 ? "INITIAL PAIR: A3 + D3" : "x → VOICE 1  ·  y → VOICE 2", 9, foreground, :right))

    annotate!(p, TEXT_LEFT, 3.68,
              text(@sprintf("STATE n = %d", orbit_index), 10, foreground, :left))
    annotate!(p, TEXT_LEFT, 3.20,
              text(@sprintf("x = %+.5f", scene.xs[orbit_index]), 14, foreground, :left))
    annotate!(p, TEXT_LEFT, 2.78,
              text(@sprintf("y = %+.5f", scene.ys[orbit_index]), 14, foreground, :left))
    annotate!(p, TEXT_RIGHT, 4.02,
              text(uppercase(interval_name(semitones)) * @sprintf(" · %d st", semitones),
                   17, foreground, :right))
    for (voice, anchor) in enumerate((8.4, TEXT_RIGHT))
        annotate!(p, anchor, 3.48,
                  text(note_name(notes[voice]), 26, foreground, :right))
        annotate!(p, anchor, 2.92,
                  text(@sprintf("%.2f Hz", midi_freq(notes[voice])), 11, foreground, :right))
    end
    keyboard_notes = note_time < NOTE - NOTE_GAP ? notes : ()
    draw_keyboard(p, keyboard_notes, note_time)
    annotate!(p, 6.0, 0.58,
              text("RING: COMPUTED STATE  ·  POINT: VISUAL INTERPOLATION", 8, foreground, :center))
    savefig(p, path)
    return p
end

function make_video_only()

    mkpath(OUTPUT_DIR)
    for frame in 1:number_of_frames()
        path = joinpath(FRAME_DIR, @sprintf("frame_%05d.png", frame))
        isfile(path) || error("Missing frame $frame: $path")
    end
    isfile(VIDEO_MARKER) && rm(VIDEO_MARKER)
    pattern = joinpath(FRAME_DIR, "frame_%05d.png")
    fade_out_start = max(0, DURATION - 0.8)

    fades = "pad=$WIDTH:$HEIGHT:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=$FPS,fade=t=out:st=$fade_out_start:d=0.8"
    frames = number_of_frames()
    FFMPEG.ffmpeg_exe(`-hide_banner -y -framerate $FPS -start_number 1 -i $pattern -frames:v $frames -vf $fades -c:v libx264 -profile:v high -level:v 4.0 -preset medium -tune animation -crf 14 -maxrate 8M -bufsize 16M -pix_fmt yuv420p -movflags +faststart $VIDEO_ONLY`)
    write(VIDEO_MARKER, VIDEO_SCENE_ID)
end

function validate_scene_video()
    isfile(VIDEO_ONLY) && isfile(VIDEO_MARKER) && read(VIDEO_MARKER, String) == VIDEO_SCENE_ID ||
        error("No finished video for this Steinway scene version. Run the full render first. " *
              "Other scene versions cannot be used for this remux.")
    VIDEO_ONLY
end

function add_audio(; audio_path=DEFAULT_AUDIO)
    source = validate_external_audio(audio_path)
    validate_scene_video()
    fade_start = max(0, DURATION - 0.8)
    frames = number_of_frames()

    audio_filter = "asetpts=PTS-STARTPTS,apad,atrim=duration=$DURATION,afade=t=out:st=$fade_start:d=0.8"
    FFMPEG.ffmpeg_exe(`-hide_banner -y -i $VIDEO_ONLY -i $source -map 0:v:0 -map 1:a:0 -map_metadata -1 -map_chapters -1 -c:v copy -frames:v $frames -af $audio_filter -c:a aac -profile:a aac_low -b:a 256k -ar $SAMPLE_RATE -ac 2 -t $DURATION -movflags +faststart -metadata comment=$AUDIO_CREDIT $FINAL_VIDEO`)
    FINAL_VIDEO
end

end
# ARISTOTEL - METAPHYSICS, I.1, 980a21:
# "All men by nature desire to know. An indication of this is our delight in our senses;
#  for even apart from their usefulness they are loved for themselves; and above all others the sense of sight."

module ChromaticA2
using Plots
using FFMPEG
using Printf
gr()

const PROJECT_ROOT = getfield(parentmodule(@__MODULE__), :PROJECT_ROOT)

const FPS = 24
const NOTE_COUNT = 32
const WIDTH = 1080
const HEIGHT = 1080
const SAMPLE_RATE = 44100
const NOTE = 1.75
const TAIL_DURATION = 0.0
const DURATION = NOTE_COUNT * NOTE + TAIL_DURATION
const NOTE_GAP = 0.072
const FIXED_MIDI_VELOCITY = 88

const OUTPUT_DIR = joinpath(PROJECT_ROOT, "henon_a2_a5_chromatic_render")
const FRAME_DIR = joinpath(OUTPUT_DIR, "frames")
const DEFAULT_AUDIO = joinpath(PROJECT_ROOT, "henon_a2_a5_chromatic.wav")
const VIDEO_ONLY = joinpath(OUTPUT_DIR, "henon_duet_silent.mp4")
const FINAL_VIDEO = joinpath(OUTPUT_DIR, "henon_a2_a5_chromatic.mp4")
const MIDI_FILE = joinpath(PROJECT_ROOT, "henon_a2_a5_chromatic_for_logic.mid")
const PIANO_CREDIT = "PIANO: STEINWAY / LOGIC PRO"
const AUDIO_CREDIT = "HENON MUSIC. Steinway Grand Piano, Logic Pro. Direct coordinate sonification: x selects voice 1 and y selects voice 2 from all 37 chromatic notes in A2-A5. The first pair is the supplied A3/D3 seed; later pairs are mapped directly from current x and y with no interval menu, melodic jump menu or voice ordering. The coordinates remain coupled by the Henon map. 32 pairs from consecutive iterates, 1.75 seconds each, 56 seconds total. The dotted cloud uses actual computed states; smooth cursor motion is visual interpolation."
const VIDEO_SCENE_ID = "henon-speaks-music-175-v1|range=A2-A5|rule=chromatic|1080x1080|24fps|56s|1344frames|pair=1.75s|gate=1.678s|step=1|opening57-50|display-margin-9-center5.98-width11.3-alpha.11-.74|counter=PAIR01-32|heading=HENON|formula=20-v2"
const VIDEO_MARKER = joinpath(OUTPUT_DIR, "video_scene.txt")

function midi_write_be(io, value::Integer, bytes::Integer)
    value >= 0 || throw(ArgumentError("MIDI integer must be nonnegative."))
    for shift in (8 * (bytes - 1)):-8:0
        write(io, UInt8((value >> shift) & 0xff))
    end
end

function midi_write_vlq(io, value::Integer)
    0 <= value <= 0x0fffffff ||
        throw(ArgumentError("MIDI variable-length value is out of range."))
    encoded = UInt8[UInt8(value & 0x7f)]
    value >>= 7
    while value > 0
        push!(encoded, UInt8((value & 0x7f) | 0x80))
        value >>= 7
    end
    write(io, reverse(encoded))
end

function midi_meta(io, kind::Integer, payload::AbstractVector{UInt8})
    write(io, UInt8[0xff, UInt8(kind)])
    midi_write_vlq(io, length(payload))
    write(io, payload)
end

function midi_track(io, data::Vector{UInt8})
    length(data) <= typemax(UInt32) ||
        throw(ArgumentError("MIDI track exceeds the file format limit."))
    write(io, codeunits("MTrk"))
    midi_write_be(io, length(data), 4)
    write(io, data)
end

function write_midi(path, voices, velocities;
                    note=NOTE, note_gap=NOTE_GAP, duration=DURATION)
    ndims(voices) == 2 && size(voices, 2) == 2 ||
        throw(ArgumentError("MIDI export expects two voice columns."))
    size(voices) == size(velocities) ||
        throw(ArgumentError("Notes and velocities must have the same shape."))
    isfinite(note) && isfinite(note_gap) && isfinite(duration) &&
        0 < note_gap < note && duration > 0 ||
        throw(ArgumentError("Invalid MIDI timing settings."))
    all(m -> m isa Integer && 0 <= m <= 127, voices) ||
        throw(ArgumentError("MIDI notes must be integers from 0 to 127."))
    all(isfinite, velocities) ||
        throw(ArgumentError("MIDI velocities must be finite."))

    ticks_per_second = 1000
    duration_ticks = round(Int, duration * ticks_per_second)
    duration_ticks <= 0x0fffffff ||
        throw(ArgumentError("MIDI duration is too long."))

    events = [Tuple{Int,Int,Vector{UInt8}}[] for _ in 1:2]
    for k in axes(voices, 1)
        onset = round(Int, (k - 1) * note * ticks_per_second)
        release = round(Int, (k * note - note_gap) * ticks_per_second)
        0 <= onset < release <= duration_ticks ||
            throw(ArgumentError("A MIDI note falls outside the duration or is shorter than 1 ms."))
        for voice in 1:2
            channel = voice - 1
            midi_note = UInt8(voices[k, voice])

            velocity = UInt8(round(Int, clamp(velocities[k, voice], 1 / 127, 1) * 127))
            push!(events[voice], (onset, 1, UInt8[0x90 + channel, midi_note, velocity]))
            push!(events[voice], (release, 0, UInt8[0x80 + channel, midi_note, 0]))
        end
    end

    open(path, "w") do io
        write(io, codeunits("MThd"))
        midi_write_be(io, 6, 4)
        midi_write_be(io, 1, 2)
        midi_write_be(io, 3, 2)
        midi_write_be(io, 1000, 2)

        tempo_track = IOBuffer()
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x03, collect(codeunits("Henon chromatic XY - no key or interval menu - 32 pairs")))
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x51, UInt8[0x0f, 0x42, 0x40])
        midi_write_vlq(tempo_track, 0)
        midi_meta(tempo_track, 0x58, UInt8[4, 2, 24, 8])

        midi_write_vlq(tempo_track, duration_ticks)
        midi_meta(tempo_track, 0x2f, UInt8[])
        midi_track(io, take!(tempo_track))

        for voice in 1:2
            channel = voice - 1
            track = IOBuffer()
            midi_write_vlq(track, 0)
            midi_meta(track, 0x03, collect(codeunits(("Voice 1 - X coordinate", "Voice 2 - Y coordinate")[voice])))
            midi_write_vlq(track, 0)
            write(track, UInt8[0xc0 + channel, 0])
            midi_write_vlq(track, 0)
            write(track, UInt8[0xb0 + channel, 10, (42, 86)[voice]])
            midi_write_vlq(track, 0)
            write(track, UInt8[0xb0 + channel, 7, (100, 100)[voice]])

            previous_tick = 0

            sort!(events[voice]; by=event -> (event[1], event[2]))
            for (tick, _, data) in events[voice]
                midi_write_vlq(track, tick - previous_tick)
                write(track, data)
                previous_tick = tick
            end
            midi_write_vlq(track, duration_ticks - previous_tick)
            midi_meta(track, 0x2f, UInt8[])
            midi_track(io, take!(track))
        end
    end
    return path
end

const A = 1.4
const B = 0.3
const X0 = 0.1
const Y0 = 0.0
const BURN_IN = 10000
const ATTRACTOR_POINTS = 60000

const DISPLAY_POINT_COUNT = 3000
const ORBIT_STEP = 1
# HEISENBERG UNCERTAINTY PRINCIPLE:
# ∆(x) * ∆(p) >= ℏ / 2
# Precision has a fundamental limit. //:>
const ATTRACTOR_CENTER = (5.98, 7.10)
const ATTRACTOR_WIDTH = 11.3
const ATTRACTOR_HEIGHT = 5.3
const KEYBOARD_ALPHA = 0.40
const TEXT_LEFT = 0.4
const TEXT_RIGHT = 11.6

const INITIAL_NOTES = (57, 50)
const LOW_MIDI = 45
const HIGH_MIDI = 81
const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const PITCH_NOTES = collect(LOW_MIDI:HIGH_MIDI)
const WHITE_KEY_NOTES = [m for m in LOW_MIDI:HIGH_MIDI if mod(m, 12) in (0, 2, 4, 5, 7, 9, 11)]

const MARKER_COLOR = "#ffffff"
const INTERVAL_NAMES = (
    "unison", "minor 2nd", "major 2nd", "minor 3rd", "major 3rd",
    "perfect 4th", "tritone", "perfect 5th", "minor 6th", "major 6th",
    "minor 7th", "major 7th", "octave"
)

midi_freq(m) = 440.0 * 2.0^((m - 69) / 12)
note_name(m) = NOTE_NAMES[mod(m, 12) + 1] * string(fld(m, 12) - 1)
interval_semitones(a, b) = abs(a - b)
function interval_name(semitones::Integer)
    0 <= semitones <= HIGH_MIDI - LOW_MIDI ||
        throw(ArgumentError("Interval outside the A2-A5 range: $semitones."))
    semitones <= 12 && return INTERVAL_NAMES[semitones + 1]
    octaves, remainder = divrem(semitones, 12)
    remainder == 0 && return "$octaves octaves"
    "$octaves oct + " * INTERVAL_NAMES[remainder + 1]
end
number_of_notes() = NOTE_COUNT
number_of_frames() = round(Int, FPS * DURATION)

function validate_settings()
    @assert FPS > 0 && SAMPLE_RATE > 0 && DURATION > 0
    @assert 0 < NOTE_GAP < NOTE
    @assert FIXED_MIDI_VELOCITY isa Integer && 1 <= FIXED_MIDI_VELOCITY <= 127
    @assert isfinite(TAIL_DURATION) && TAIL_DURATION >= 0
    @assert isapprox(DURATION, number_of_notes() * NOTE + TAIL_DURATION; atol=1e-10, rtol=0) "Use the note sequence duration plus the tail."
    @assert isapprox(FPS * DURATION, number_of_frames(); atol=1e-10, rtol=0) "Use a whole number of frames."
    @assert isapprox(FPS * NOTE, round(Int, FPS * NOTE); atol=1e-10, rtol=0) "Use a whole number of frames per note."
    @assert number_of_notes() >= 1 && ORBIT_STEP == 1
    @assert B != 0 && BURN_IN >= 1
    @assert all(note -> note in PITCH_NOTES, INITIAL_NOTES)
    @assert ATTRACTOR_POINTS >= number_of_notes() * ORBIT_STEP
    @assert 1 <= DISPLAY_POINT_COUNT <= ATTRACTOR_POINTS
    @assert 0 <= KEYBOARD_ALPHA <= 1
    @assert midi_freq(HIGH_MIDI) < SAMPLE_RATE / 2
end

function henon_points(n)
    xs = zeros(Float64, n)
    ys = zeros(Float64, n)
    x, y = X0, Y0
    for i in 1:n

        xn = 1.0 - A * x * x + y
        yn = B * x
        x, y = xn, yn
        isfinite(x) && isfinite(y) || error("Orbit diverged at iteration $i.")
        xs[i], ys[i] = x, y
    end
    xs, ys
end

# Between the minimum and the maximum lies everything the system has become. //;>

function coordinate_note(value, minimum, maximum)
    maximum > minimum || throw(ArgumentError("Coordinate reference range must be positive."))
    position = clamp((value - minimum) / (maximum - minimum), 0.0, 1.0)
    index = min(floor(Int, position * length(PITCH_NOTES)) + 1, length(PITCH_NOTES))
    PITCH_NOTES[index]
end

function make_sequence(xs, ys, start)
    count = number_of_notes()
    indices = [start + (k - 1) * ORBIT_STEP for k in 1:count]
    xmin, xmax = extrema(@view xs[start:end])
    ymin, ymax = extrema(@view ys[start:end])
    voices = zeros(Int, count, 2)
    for k in 1:count
        n = indices[k]
        if k == 1
            voices[k, 1], voices[k, 2] = INITIAL_NOTES
        else
            voices[k, 1] = coordinate_note(xs[n], xmin, xmax)
            voices[k, 2] = coordinate_note(ys[n], ymin, ymax)
        end
    end
    velocities = fill(FIXED_MIDI_VELOCITY / 127.0, count, 2)
    voices, velocities, indices
end

function make_midi(voices, velocities)
    write_midi(MIDI_FILE, voices, velocities)
    println("MIDI saved: ", abspath(MIDI_FILE))
    flush(stdout)
end

function validate_external_audio(path)
    absolute_path = abspath(expanduser(path))
    isfile(absolute_path) || error(
        "Finished WAV not found: $absolute_path\n" *
        "Save a stereo bounce from Logic Pro as henon_a2_a5_chromatic.wav in $PROJECT_ROOT " *
        "or use --audio /absolute/path/to/audio.wav.\n" *
        "Audio is not required for a preview: julia henon_speaks_music.jl --preview"
    )
    report = try
        read(`$(FFMPEG.ffprobe()) -v error -select_streams a:0 -show_entries stream=channels,sample_rate:format=format_name,duration -of default=noprint_wrappers=1 $absolute_path`, String)
    catch err
        error("Could not read WAV $absolute_path: $(sprint(showerror, err))")
    end
    fields = Dict{String, String}()
    for line in split(chomp(report), '\n')
        parts = split(line, '='; limit=2)
        length(parts) == 2 && (fields[parts[1]] = parts[2])
    end
    get(fields, "format_name", "") == "wav" || error("A stereo Logic Pro bounce in WAV format is required: $absolute_path")
    get(fields, "channels", "") == "2" || error("The WAV must contain two audio channels (stereo): $absolute_path")
    seconds = tryparse(Float64, get(fields, "duration", ""))
    !isnothing(seconds) && isfinite(seconds) && seconds > 0 || error("Could not determine WAV duration.")
    seconds + 1 / SAMPLE_RATE >= DURATION || error(@sprintf("WAV is only %.3f s; this scene requires %.3f s including a real piano tail. Supply the new bounce rather than padding silence.", seconds, DURATION))
    println("Finished Logic Pro audio: ", absolute_path)
    println(@sprintf("Audio: %.3f s; video: %.3f s. The first MIDI note must start at 0 s.", seconds, DURATION))
    flush(stdout)
    absolute_path
end

# Chaos does not ask to be understood. Neither does beauty. //;> 

function prepare_scene()
    validate_settings()
    first_index = BURN_IN + 1
    last_index = BURN_IN + ATTRACTOR_POINTS
    xs, ys = henon_points(last_index)
    voices, velocities, indices = make_sequence(xs, ys, first_index)
    transform = attractor_transform(xs, ys, first_index, last_index)
    display_indices = round.(Int, range(1, length(transform.cloud_x); length=DISPLAY_POINT_COUNT))
    (; xs, ys, voices, velocities, indices, first_index, last_index, transform, display_indices)
end

function render_scene_frame(path, scene, frame)
    1 <= frame <= number_of_frames() || throw(ArgumentError("Frame outside the range 1:$(number_of_frames())."))
    draw_frame(path, scene, frame)
end

function marker_position(xs, ys, indices, time)
    note_index = clamp(floor(Int, time / NOTE) + 1, 1, length(indices))
    orbit_index = indices[note_index]
    next_index = indices[min(note_index + 1, length(indices))]
    phase = clamp((time - (note_index - 1) * NOTE) / NOTE, 0.0, 1.0)

    eased = phase^3 * (10.0 + phase * (-15.0 + 6.0 * phase))
    current_x = (1.0 - eased) * xs[orbit_index] + eased * xs[next_index]
    current_y = (1.0 - eased) * ys[orbit_index] + eased * ys[next_index]
    current_x, current_y, note_index, orbit_index
end

function attractor_transform(xs, ys, first_index, last_index)
    xmin, xmax = extrema(@view xs[first_index:last_index])
    ymin, ymax = extrema(@view ys[first_index:last_index])

    scale = min(ATTRACTOR_WIDTH / (xmax - xmin), ATTRACTOR_HEIGHT / (ymax - ymin))
    scale_x = scale_y = scale
    xmid, ymid = (xmin + xmax) / 2, (ymin + ymax) / 2
    cloud_x = ATTRACTOR_CENTER[1] .+ scale_x .* (@view(xs[first_index:last_index]) .- xmid)
    cloud_y = ATTRACTOR_CENTER[2] .+ scale_y .* (@view(ys[first_index:last_index]) .- ymid)
    (scale_x=scale_x, scale_y=scale_y, xmid=xmid, ymid=ymid, cloud_x=cloud_x, cloud_y=cloud_y)
end

screen_x(x, transform) = ATTRACTOR_CENTER[1] + transform.scale_x * (x - transform.xmid)
screen_y(y, transform) = ATTRACTOR_CENTER[2] + transform.scale_y * (y - transform.ymid)

# Mathematic defines the possible.
# Music gives it a voice.
# The Muse demands a proof. //;> 

function transition_geometry(scene, time)
    current_x, current_y, note_index, orbit_index =
        marker_position(scene.xs, scene.ys, scene.indices, time)
    transform = scene.transform
    state = (screen_x(scene.xs[orbit_index], transform), screen_y(scene.ys[orbit_index], transform))
    cursor = (screen_x(current_x, transform), screen_y(current_y, transform))
    target_index = note_index < length(scene.indices) ? scene.indices[note_index + 1] : nothing
    target = isnothing(target_index) ? nothing :
        (screen_x(scene.xs[target_index], transform), screen_y(scene.ys[target_index], transform))
    (; current_x, current_y, note_index, orbit_index, state, cursor, target_index, target)
end

function draw_keyboard(p, notes, note_time=0.0)
    left_edge, right_edge = TEXT_LEFT, TEXT_RIGHT
    bottom, top = 1.10, 2.45
    key_width = (right_edge - left_edge) / length(WHITE_KEY_NOTES)
    pulse = exp(-max(0.0, note_time) / 0.35)

    for (key_index, midi_note) in enumerate(WHITE_KEY_NOTES)
        any(==(midi_note), notes) || continue
        left = left_edge + (key_index - 1) * key_width
        right = left + key_width
        for (padding, opacity) in ((0.090, 0.055), (0.055, 0.095), (0.025, 0.170))
            plot!(p, Shape([left-padding, right+padding, right+padding, left-padding],
                           [bottom-padding, bottom-padding, top+padding, top+padding]),
                  fillcolor="#ffffff", fillalpha=opacity * (0.75 + 0.25 * pulse),
                  linewidth=0)
        end
    end
    for (key_index, midi_note) in enumerate(WHITE_KEY_NOTES)
        left = left_edge + (key_index - 1) * key_width
        right = left + key_width
        active = any(==(midi_note), notes)
        if active

            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#000000", fillalpha=1.0, linewidth=0)
            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#ffffff", fillalpha=0.88 + 0.08 * pulse,
                  linecolor="#ffffff", linealpha=0.90 + 0.10 * pulse,
                  linewidth=0.85 + 0.15 * pulse)
        else
            plot!(p, Shape([left, right, right, left], [bottom, bottom, top, top]),
                  fillcolor="#eeeeee", fillalpha=KEYBOARD_ALPHA,
                  linecolor="#a0a0a0", linealpha=0.30, linewidth=0.6)
        end
        label = mod(midi_note, 12) == 0 ? note_name(midi_note) : NOTE_NAMES[mod(midi_note, 12)+1]
        if active

            outline = 0.009
            for (dx, dy) in ((-outline, -outline), (0.0, -outline), (outline, -outline),
                             (-outline, 0.0), (outline, 0.0),
                             (-outline, outline), (0.0, outline), (outline, outline))
                annotate!(p, (left + right) / 2 + dx, bottom + 0.14 + dy,
                          text(label, 9, "#666666", :center))
            end
        end
        annotate!(p, (left + right) / 2, bottom + 0.14,
                  text(label, 9, "#ffffff", :center))
    end
    for midi_note in LOW_MIDI:HIGH_MIDI
        mod(midi_note, 12) in (1, 3, 6, 8, 10) || continue
        boundary = left_edge + searchsortedlast(WHITE_KEY_NOTES, midi_note) * key_width
        left, right = boundary - 0.29 * key_width, boundary + 0.29 * key_width
        black_bottom = bottom + 0.38 * (top - bottom)
        active = any(==(midi_note), notes)
        if active
            for (padding, opacity) in ((0.045, 0.13), (0.020, 0.23))
                plot!(p, Shape([left-padding, right+padding, right+padding, left-padding],
                               [black_bottom-padding, black_bottom-padding, top+padding, top+padding]),
                      fillcolor="#ffffff", fillalpha=opacity * (0.75 + 0.25*pulse), linewidth=0)
            end
        end
        plot!(p, Shape([left, right, right, left], [black_bottom, black_bottom, top, top]),
              fillcolor=active ? "#ffffff" : "#000000",
              fillalpha=active ? 0.88 + 0.08*pulse : 0.90,
              linecolor="#ffffff", linealpha=active ? 0.95 : 0.0, linewidth=0.7)
        if active
            x = (left + right) / 2
            y = black_bottom + 0.13
            outline = 0.009
            for (dx,dy) in ((-outline,0.0),(outline,0.0),(0.0,-outline),(0.0,outline))
                annotate!(p,x+dx,y+dy,text(note_name(midi_note),6,"#666666",:center))
            end
            annotate!(p,x,y,text(note_name(midi_note),6,"#ffffff",:center))
        end
    end
end

function draw_frame(path, scene, frame)
    foreground, muted = "#ffffff", "#ffffff"
    time = (frame - 1) / FPS
    motion = transition_geometry(scene, time)
    current_x, current_y = motion.current_x, motion.current_y
    note_index, orbit_index = motion.note_index, motion.orbit_index
    notes = Tuple(scene.voices[note_index, :])
    semitones = interval_semitones(notes...)
    note_time = time - (note_index - 1) * NOTE
    pulse = maximum(@view scene.velocities[note_index, :]) * exp(-note_time / 0.22)
    transform = scene.transform
    p = plot(xlims=(0, 12), ylims=(0, 12), widen=false, size=(WIDTH, HEIGHT),
             aspect_ratio=:equal, axis=false, grid=false, legend=false,
             background_color="#000000", foreground_color=foreground,
             fontfamily="Helvetica", margin=-9 * Plots.mm)

    scatter!(p, transform.cloud_x, transform.cloud_y,
             markersize=0.48, markercolor="#dddddd", markeralpha=0.11,
             markerstrokewidth=0)

    scatter!(p, transform.cloud_x[scene.display_indices], transform.cloud_y[scene.display_indices],
             markersize=0.88, markercolor="#eeeeee", markeralpha=0.74,
             markerstrokewidth=0)

    angles = range(0.0, 2pi; length=33)
    plot!(p, motion.state[1] .+ 0.055 .* cos.(angles),
             motion.state[2] .+ 0.055 .* sin.(angles),
          color="#ffffff", linealpha=0.75, linewidth=1.0)

    outer_radius, inner_radius = 28 + 4 * pulse, 12 + 1.5 * pulse
    sigma = 6.5 + 0.7 * pulse
    edge = exp(-0.5 * ((outer_radius - inner_radius) / sigma)^2)
    previous_opacity = 0.0
    for radius in range(outer_radius, inner_radius; length=16)
        target_opacity = (0.30 + 0.06 * pulse) *
            (exp(-0.5 * ((radius - inner_radius) / sigma)^2) - edge) / (1.0 - edge)
        opacity = clamp((target_opacity - previous_opacity) / (1.0 - previous_opacity), 0.0, 1.0)
        previous_opacity = target_opacity
        opacity <= 1e-6 && continue
        scatter!(p, [screen_x(current_x, transform)], [screen_y(current_y, transform)],
                 markersize=radius, markercolor=MARKER_COLOR,
                 markerstrokewidth=0, markeralpha=opacity)
    end
    scatter!(p, [screen_x(current_x, transform)], [screen_y(current_y, transform)],
             markersize=10.5 + 1.5 * pulse, markercolor=MARKER_COLOR,
             markerstrokecolor=MARKER_COLOR, markerstrokewidth=1.4,
             markeralpha=1.0, markerstrokealpha=1.0)

    annotate!(p, TEXT_LEFT, 11.30, text("HENON", 23, foreground, :left))
    annotate!(p, TEXT_RIGHT, 11.30,
              text(@sprintf("xₙ₊₁ = 1 − %.1fxₙ² + yₙ;    yₙ₊₁ = %.1fxₙ", A, B),
                   20, foreground, :right))
    annotate!(p, TEXT_LEFT, 10.82,
              text("CHROMATIC  ·  TWO VOICES  ·  A2–A5", 9, foreground, :left))
    annotate!(p, TEXT_LEFT, 10.42,
              text(@sprintf("PAIR %02d/%02d", note_index, NOTE_COUNT), 9, foreground, :left))
    annotate!(p, TEXT_RIGHT, 10.82,
              text(note_index == 1 ? "INITIAL PAIR: A3 + D3" : "x → VOICE 1  ·  y → VOICE 2", 9, foreground, :right))

    annotate!(p, TEXT_LEFT, 3.68,
              text(@sprintf("STATE n = %d", orbit_index), 10, foreground, :left))
    annotate!(p, TEXT_LEFT, 3.20,
              text(@sprintf("x = %+.5f", scene.xs[orbit_index]), 14, foreground, :left))
    annotate!(p, TEXT_LEFT, 2.78,
              text(@sprintf("y = %+.5f", scene.ys[orbit_index]), 14, foreground, :left))
    annotate!(p, TEXT_RIGHT, 4.02,
              text(uppercase(interval_name(semitones)) * @sprintf(" · %d st", semitones),
                   17, foreground, :right))
    for (voice, anchor) in enumerate((8.4, TEXT_RIGHT))
        annotate!(p, anchor, 3.48,
                  text(note_name(notes[voice]), 26, foreground, :right))
        annotate!(p, anchor, 2.92,
                  text(@sprintf("%.2f Hz", midi_freq(notes[voice])), 11, foreground, :right))
    end
    keyboard_notes = note_time < NOTE - NOTE_GAP ? notes : ()
    draw_keyboard(p, keyboard_notes, note_time)
    annotate!(p, 6.0, 0.58,
              text("RING: COMPUTED STATE  ·  POINT: VISUAL INTERPOLATION", 8, foreground, :center))
    savefig(p, path)
    return p
end

function make_video_only()

    mkpath(OUTPUT_DIR)
    for frame in 1:number_of_frames()
        path = joinpath(FRAME_DIR, @sprintf("frame_%05d.png", frame))
        isfile(path) || error("Missing frame $frame: $path")
    end
    isfile(VIDEO_MARKER) && rm(VIDEO_MARKER)
    pattern = joinpath(FRAME_DIR, "frame_%05d.png")
    fade_out_start = max(0, DURATION - 0.8)

    fades = "pad=$WIDTH:$HEIGHT:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=$FPS,fade=t=out:st=$fade_out_start:d=0.8"
    frames = number_of_frames()
    FFMPEG.ffmpeg_exe(`-hide_banner -y -framerate $FPS -start_number 1 -i $pattern -frames:v $frames -vf $fades -c:v libx264 -profile:v high -level:v 4.0 -preset medium -tune animation -crf 14 -maxrate 8M -bufsize 16M -pix_fmt yuv420p -movflags +faststart $VIDEO_ONLY`)
    write(VIDEO_MARKER, VIDEO_SCENE_ID)
end

function validate_scene_video()
    isfile(VIDEO_ONLY) && isfile(VIDEO_MARKER) && read(VIDEO_MARKER, String) == VIDEO_SCENE_ID ||
        error("No finished video for this Steinway scene version. Run the full render first. " *
              "Other scene versions cannot be used for this remux.")
    VIDEO_ONLY
end

function add_audio(; audio_path=DEFAULT_AUDIO)
    source = validate_external_audio(audio_path)
    validate_scene_video()
    fade_start = max(0, DURATION - 0.8)
    frames = number_of_frames()
    # BAYESIAN PERCEPTION:
    # P(H|D) = P(D|H) * P(H) / P(D)
    # The brain may infer causes from incomplete evidence.
    # Perception is an inference, not a direct copy of reality.
    # The Muse wonders what remains beyond the model. //:>
    audio_filter = "asetpts=PTS-STARTPTS,apad,atrim=duration=$DURATION,afade=t=out:st=$fade_start:d=0.8"
    FFMPEG.ffmpeg_exe(`-hide_banner -y -i $VIDEO_ONLY -i $source -map 0:v:0 -map 1:a:0 -map_metadata -1 -map_chapters -1 -c:v copy -frames:v $frames -af $audio_filter -c:a aac -profile:a aac_low -b:a 256k -ar $SAMPLE_RATE -ac 2 -t $DURATION -movflags +faststart -metadata comment=$AUDIO_CREDIT $FINAL_VIDEO`)
    FINAL_VIDEO
end

end

using Plots, FFMPEG, Printf

const MANIAC_FONT = joinpath(PROJECT_ROOT, "MonomaniacOne-Regular")
const SPEAKS_FPS = HarmonicA2.FPS
const CARD_FRAMES = 112
const CARD_SECONDS = CARD_FRAMES / SPEAKS_FPS
const MUSIC_FRAMES = HarmonicA2.number_of_frames()
const MUSIC_SECONDS = HarmonicA2.DURATION
const SECTION_FRAMES = CARD_FRAMES + MUSIC_FRAMES
const SECTION_SECONDS = SECTION_FRAMES / SPEAKS_FPS
const FILM_FRAMES = 3 * SECTION_FRAMES
const FILM_SECONDS = FILM_FRAMES / SPEAKS_FPS

const CARD_FADE_IN = 0.3
const CARD_FADE_OUT = 0.4
const MUSIC_FADE_OUT = 0.8
const SPEAKS_EDITIONS = (
    (key="a2_a5", range="A2-A5", engines=(HarmonicA2, DirectA2, ChromaticA2)),
)
const RULE_KEYS = ("harmonic", "direct", "chromatic")  # Rules? The Muse has never heard of them. But must we ?  //;>
edition_dir(edition) = PROJECT_ROOT
edition_video(edition) = joinpath(edition_dir(edition), "henon_speaks_music_" * edition.key * ".mp4")

function section_label(edition, index)
    name = index == 1 ? "C MAJOR $(edition.range) + INTERVAL RULES" :
           index == 2 ? "C MAJOR $(edition.range) + DIRECT X/Y" :
                        "CHROMATIC $(edition.range) + DIRECT X/Y"
    @sprintf("%02d ", index) * name
end

function flat_probe_fields(report)
    fields = Dict{String,String}()
    for line in split(chomp(report), '\n')
        pair = split(line, '='; limit=2)
        length(pair) == 2 && (fields[pair[1]] = pair[2])
    end
    fields
end

function cached_video_matches(m)
    isfile(m.VIDEO_ONLY) && isfile(m.VIDEO_MARKER) || return false
    read(m.VIDEO_MARKER, String) == m.VIDEO_SCENE_ID || return false
    report = try
        read(`$(FFMPEG.ffprobe()) -v error -select_streams v:0 -count_frames -show_entries stream=codec_name,width,height,pix_fmt,avg_frame_rate,nb_read_frames,duration -of default=noprint_wrappers=1 $(m.VIDEO_ONLY)`, String)
    catch
        return false
    end
    values = flat_probe_fields(report)
    get(values,"codec_name","") == "h264" && get(values,"pix_fmt","") == "yuv420p" &&
    get(values,"width","") == "1080" && get(values,"height","") == "1080" &&
    get(values,"avg_frame_rate","") == "$(m.FPS)/1" &&
    tryparse(Int,get(values,"nb_read_frames","")) == m.number_of_frames() &&
    tryparse(Float64,get(values,"duration","")) == m.DURATION
end

function render_silent_variant(m, scene; force=false)
    !force && cached_video_matches(m) && return
    mkpath(m.OUTPUT_DIR)
    isfile(m.VIDEO_MARKER) && rm(m.VIDEO_MARKER)
    scratch = joinpath(m.OUTPUT_DIR, "current_frame.png")
    frames = m.number_of_frames()
    fade_start = m.DURATION - MUSIC_FADE_OUT
    filter = "pad=1080:1080:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=$(m.FPS),fade=t=out:st=$fade_start:d=$MUSIC_FADE_OUT"
    command = `$(FFMPEG.ffmpeg()) -hide_banner -loglevel warning -y -f image2pipe -vcodec png -framerate $(m.FPS) -i pipe:0 -frames:v $frames -vf $filter -c:v libx264 -profile:v high -level:v 4.0 -preset medium -tune animation -crf 14 -maxrate 8M -bufsize 16M -pix_fmt yuv420p -movflags +faststart $(m.VIDEO_ONLY)`
    println("Rendering ", nameof(m), ": ", frames, " frames...")
    flush(stdout)
    try
        open(command,"w") do encoder
            for frame in 1:frames
                m.render_scene_frame(scratch, scene, frame)
                write(encoder, read(scratch))
                if frame == 1 || frame % m.FPS == 0 || frame == frames
                    println(nameof(m), ": frame ",frame," / ",frames)
                    flush(stdout)
                end
                frame % (2*m.FPS) == 0 && GC.gc(false)
            end
        end
    catch exception
        error("Picture rendering or encoding failed (" * string(typeof(exception)) * "). No cache marker was written.")
    finally
        isfile(scratch) && rm(scratch)
    end
    write(m.VIDEO_MARKER,m.VIDEO_SCENE_ID)
    cached_video_matches(m) || error("Encoded picture failed its format, frame-count or duration check.")
end

function render_title_card(path, subtitle)
    p = plot(xlims=(0,1),ylims=(0,1),widen=false,size=(1080,1080),
        aspect_ratio=:equal,axis=false,grid=false,legend=false,
        background_color="#000000",foreground_color="#ffffff",
        fontfamily=MANIAC_FONT,margin=0*Plots.mm)
    isfile(MANIAC_FONT * ".ttf") || error("Keep MonomaniacOne-Regular.ttf in $PROJECT_ROOT.")
    annotate!(p,0.485,0.605,text("VIVIMUSE",28,"#ffffff",:center,MANIAC_FONT))
    annotate!(p,0.485,0.515,text("[ HENON_SPEAKS_MUSIC ]",34,"#ffffff",:center,MANIAC_FONT))
    annotate!(p,0.485,0.425,text(subtitle,17,"#ffffff",:center,MANIAC_FONT))
    savefig(p,path)
    path
end

function render_banner(path, subtitle)
    p = plot(xlims=(0,1),ylims=(0,1),size=(1080,40),
        background_color="#000000",foreground_color="#ffffff",legend=false,
        framestyle=:none,ticks=false,grid=false,margin=0*Plots.mm)
    annotate!(p,0.5,0.5,text(subtitle,10,"#ffffff",:center))
    savefig(p,path)
    path
end

function write_engine_table(edition, part, m, scene)
    path=joinpath(PROJECT_ROOT,"henon_$(edition.key)_$(RULE_KEYS[part])_orbit_data.tsv")
    open(path,"w") do io
        println(io,"event\torbit_n\tx\ty\tnote_a\tnote_b\tname_a\tname_b\tfrequency_a_hz\tfrequency_b_hz\tvelocity_a\tvelocity_b\tinterval_st\tinterval_name\tonset_s\tnoteoff_s")
        for event in 1:m.NOTE_COUNT
            n=scene.indices[event];a,b=scene.voices[event,:];distance=abs(a-b)
            println(io,join((event,n,scene.xs[n],scene.ys[n],a,b,
                m.note_name(a),m.note_name(b),m.midi_freq(a),m.midi_freq(b),
                scene.velocities[event,1],scene.velocities[event,2],distance,m.interval_name(distance),
                (event-1)*m.NOTE,event*m.NOTE-m.NOTE_GAP),'\t'))
        end
    end
    path
end

function write_note_timeline(edition, scenes)
    path = joinpath(PROJECT_ROOT,"notes_" * edition.key * ".tsv")
    open(path,"w") do io
        println(io,"edition\tvariant\tevent\tsection_start_s\tmusic_start_s\tcombined_onset_s\tcombined_noteoff_s\torbit_n\tx\ty\tnote_a\tnote_b\tname_a\tname_b\tfrequency_a_hz\tfrequency_b_hz\tinterval_st\tinterval_name")
        for (part,(m,scene)) in enumerate(zip(edition.engines,scenes))
            chapter_start=(part-1)*SECTION_FRAMES/SPEAKS_FPS
            music_start=((part-1)*SECTION_FRAMES+CARD_FRAMES)/SPEAKS_FPS
            for event in 1:m.NOTE_COUNT
                n=scene.indices[event];a,b=scene.voices[event,:];distance=abs(a-b)
                println(io,join((edition.range,part,event,chapter_start,music_start,
                    music_start+(event-1)*m.NOTE,music_start+event*m.NOTE-m.NOTE_GAP,
                    n,scene.xs[n],scene.ys[n],a,b,m.note_name(a),m.note_name(b),
                    m.midi_freq(a),m.midi_freq(b),distance,m.interval_name(distance)),'\t'))
            end
        end
    end
    path
end

function write_all_timeline(paths)
    combined=joinpath(PROJECT_ROOT,"all_editions.tsv")
    open(combined,"w") do io
        for (index,path) in enumerate(paths)
            for (line_index,line) in enumerate(eachline(path))
                index>1 && line_index==1 && continue
                println(io,line)
            end
        end
    end
    println("All 96 note pairs: ",abspath(combined))
    combined
end

function write_chapters(edition)
    path=joinpath(edition_dir(edition),"chapters.ffmeta")
    open(path,"w") do io
        println(io,";FFMETADATA1\ntitle=HENON SPEAKS MUSIC - ",edition.range)
        println(io,"comment=Three authored sonifications of one Henon orbit. Each chapter has a silent ",CARD_FRAMES,"-frame title and 32 simultaneous piano pairs at ",HarmonicA2.NOTE," seconds per pair. Piano: Steinway / Logic Pro. The moving cursor is visual interpolation.")
        for part in 1:3

            println(io,"[CHAPTER]\nTIMEBASE=1/",SPEAKS_FPS,"\nSTART=",(part-1)*SECTION_FRAMES)
            println(io,"END=",part*SECTION_FRAMES,"\ntitle=",section_label(edition,part))
        end
    end
    path
end

function validate_edition_video(edition)
    path=edition_video(edition)
    video_report=try
        read(`$(FFMPEG.ffprobe()) -v error -select_streams v:0 -count_frames -show_entries stream=codec_name,width,height,pix_fmt,avg_frame_rate,nb_read_frames,duration,start_time -of default=noprint_wrappers=1 $path`,String)
    catch exception
        error("Could not verify finished video ("*string(typeof(exception))*").")
    end
    audio_report=try
        read(`$(FFMPEG.ffprobe()) -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels,duration,start_time -of default=noprint_wrappers=1 $path`,String)
    catch exception
        error("Could not verify finished audio ("*string(typeof(exception))*").")
    end
    v,a=flat_probe_fields(video_report),flat_probe_fields(audio_report)
    get(v,"codec_name","")=="h264" && get(v,"width","")=="1080" && get(v,"height","")=="1080" &&
        get(v,"pix_fmt","")=="yuv420p" && get(v,"avg_frame_rate","")=="$SPEAKS_FPS/1" &&
        tryparse(Int,get(v,"nb_read_frames",""))==FILM_FRAMES &&
        tryparse(Float64,get(v,"duration",""))==FILM_SECONDS &&
        tryparse(Float64,get(v,"start_time",""))==0 || error("The finished movie failed its picture timing/format check.")
    get(a,"codec_name","")=="aac" && get(a,"sample_rate","")=="44100" && get(a,"channels","")=="2" &&
        tryparse(Float64,get(a,"duration",""))==FILM_SECONDS &&
        tryparse(Float64,get(a,"start_time",""))==0 || error("The finished movie failed its audio timing/format check.")
    path
end

function assemble_edition(edition)
    outdir=edition_dir(edition);mkpath(outdir)
    args=String["-hide_banner","-loglevel","warning","-y"]
    chains=String[]
    music_fade_start=MUSIC_SECONDS-MUSIC_FADE_OUT
    card_fade_start=CARD_SECONDS-CARD_FADE_OUT
    card_samples=round(Int,CARD_SECONDS*44100)
    music_samples=round(Int,MUSIC_SECONDS*44100)
    for (part,m) in enumerate(edition.engines)
        subtitle=section_label(edition,part)
        card=render_title_card(joinpath(outdir,@sprintf("title_%02d.png",part)),subtitle)
        banner=render_banner(joinpath(outdir,@sprintf("banner_%02d.png",part)),subtitle)
        append!(args,["-i",m.VIDEO_ONLY,"-i",m.DEFAULT_AUDIO,
            "-loop","1","-framerate",string(SPEAKS_FPS),"-t",string(CARD_SECONDS),"-i",card,
            "-loop","1","-framerate",string(SPEAKS_FPS),"-t",string(MUSIC_SECONDS),"-i",banner])
        v,a,t,b = 4*(part-1),4*(part-1)+1,4*(part-1)+2,4*(part-1)+3
        push!(chains,"[$t:v]scale=1080:1080,setsar=1,format=yuv420p,trim=end_frame=$CARD_FRAMES,setpts=N/($SPEAKS_FPS*TB),fade=t=in:st=0:d=$CARD_FADE_IN,fade=t=out:st=$card_fade_start:d=$CARD_FADE_OUT[cardv$part]")
        push!(chains,"anullsrc=r=44100:cl=stereo,atrim=end_sample=$card_samples,asetpts=PTS-STARTPTS[carda$part]")
        push!(chains,"[$b:v]scale=1080:40,format=rgba,fade=t=out:st=$music_fade_start:d=$MUSIC_FADE_OUT:alpha=1[label$part]")
        push!(chains,"[$v:v]trim=end_frame=$MUSIC_FRAMES,setpts=N/($SPEAKS_FPS*TB)[base$part]")

        push!(chains,"[base$part][label$part]overlay=x=0:y=H-h:shortest=0:eof_action=repeat,format=yuv420p,trim=end_frame=$MUSIC_FRAMES,setpts=N/($SPEAKS_FPS*TB)[musicv$part]")

        push!(chains,"[$a:a]atrim=duration=$MUSIC_SECONDS,aresample=44100,atrim=end_sample=$music_samples,asetpts=PTS-STARTPTS,afade=t=out:st=$music_fade_start:d=$MUSIC_FADE_OUT[musica$part]")
    end
    append!(args,["-i",write_chapters(edition)])
    inputs=join(("[cardv$i][carda$i][musicv$i][musica$i]" for i in 1:3),"")
    push!(chains,inputs*"concat=n=6:v=1:a=1[joinedv][joineda]")
    push!(chains,"[joinedv]fps=$SPEAKS_FPS:start_time=0,trim=end_frame=$FILM_FRAMES,setpts=N/($SPEAKS_FPS*TB)[outv]")
    push!(chains,"[joineda]apad,atrim=end_sample=$(round(Int,FILM_SECONDS*44100)),asetpts=PTS-STARTPTS[outa]")
    append!(args,["-filter_complex",join(chains,';'),"-map","[outv]","-map","[outa]",
        "-map_metadata","12","-map_chapters","12","-t",string(FILM_SECONDS),"-r",string(SPEAKS_FPS),"-fps_mode","cfr",
        "-c:v","libx264","-profile:v","high","-level:v","4.0","-preset","medium",
        "-tune","animation","-crf","14","-maxrate","8M","-bufsize","16M",
        "-pix_fmt","yuv420p","-c:a","aac","-profile:a","aac_low","-b:a","256k",
        "-ar","44100","-ac","2","-movflags","+faststart",edition_video(edition)])
    println("Assembling ",edition.range," (",FILM_SECONDS," seconds, ",FILM_FRAMES," frames)...")
    flush(stdout)
    try
        FFMPEG.ffmpeg_exe(Cmd(args))
    catch exception
        error("Movie assembly failed ("*string(typeof(exception))*"). The source pictures and recordings are retained.")
    end
    validate_edition_video(edition)
    println("SUCCESS: ",abspath(edition_video(edition)))
end

function run_speaks_music(arguments=ARGS)
    preview=false;midi_only=false;force=false;index=1
    while index<=length(arguments)
        arg=arguments[index]
        if arg=="--preview";preview=true
        elseif arg=="--midi-only";midi_only=true
        elseif arg=="--force";force=true
        elseif arg in ("--help","-h")
            println("julia --project=. henon_speaks_music.jl [--preview|--midi-only] [--force]")
            println("Generate one A2-A5 film: 182 seconds (3:02), 3 silent title cards and 96 note pairs.")
            println("32 pairs per part, 1.75 seconds per pair. Keep the three matching 56-second WAVs and MonomaniacOne-Regular.ttf in: ", PROJECT_ROOT)
            println("The three A2-A5 MIDI sequences and mathematical note tables are exported on every run.")
            return
        else;error("Unknown option: $arg. Use --help.")
        end
        index+=1
    end
    preview && midi_only && error("Choose --preview or --midi-only.")
    mkpath(PROJECT_ROOT)
    println("Project folder: ", PROJECT_ROOT)
    flush(stdout)
    editions=SPEAKS_EDITIONS
    all_scenes=Dict{Module,Any}()
    reference=nothing
    timelines=String[]
    for edition in SPEAKS_EDITIONS
        scenes=map(m->m.prepare_scene(),edition.engines)
        for (part,(m,scene)) in enumerate(zip(edition.engines,scenes))
            @assert m.FPS==SPEAKS_FPS && m.DURATION==MUSIC_SECONDS && m.number_of_frames()==MUSIC_FRAMES
            @assert m.NOTE==1.75 && m.NOTE_COUNT==32 && Tuple(scene.voices[1,:])==(57,50)
            if isnothing(reference)
                reference=(scene.xs,scene.ys)
            else
                @assert scene.xs==reference[1] && scene.ys==reference[2]
            end
            all_scenes[m]=scene
            m.make_midi(scene.voices,scene.velocities)
            write_engine_table(edition,part,m,scene)
        end
        push!(timelines,write_note_timeline(edition,scenes))
    end
    write_all_timeline(timelines)
    @assert FILM_SECONDS==182.0 && FILM_FRAMES==4368 && MUSIC_FRAMES==1344
    midi_only && return
    if !preview
        missing=[m.DEFAULT_AUDIO for e in editions for m in e.engines if !isfile(m.DEFAULT_AUDIO)]
        isempty(missing) || error("Matching 56-second WAVs are missing. Extract the whole project into $PROJECT_ROOT. Missing: "*join(basename.(missing),", "))
        for e in editions,m in e.engines;m.validate_external_audio(m.DEFAULT_AUDIO);end
    end
    for edition in editions
        mkpath(edition_dir(edition))
        if preview
            for (part,m) in enumerate(edition.engines)
                scene=all_scenes[m]
                m.render_scene_frame(joinpath(edition_dir(edition),@sprintf("preview_%02d.png",part)),scene,1)
                last_pair_frame=round(Int,(m.NOTE_COUNT-1)*m.NOTE*m.FPS)+1
                m.render_scene_frame(joinpath(edition_dir(edition),@sprintf("preview_%02d_last.png",part)),scene,last_pair_frame)
                render_title_card(joinpath(edition_dir(edition),@sprintf("title_%02d.png",part)),section_label(edition,part))
            end
            continue
        end
        for m in edition.engines
            render_silent_variant(m,all_scenes[m];force)
        end
        assemble_edition(edition)
    end
end

if get(ENV,"HENON_SPEAKS_SKIP_MAIN","0")!="1"
    run_speaks_music()
end
# Shrödinger had a cat.
# Mathematics had an equation.
# No way I'm opening that box.
# Is harmony discovered - or imposed?
# Hmm...
# I'd better go and play Beethoven. //;> 