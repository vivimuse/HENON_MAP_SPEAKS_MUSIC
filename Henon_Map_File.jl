using Plots
using FFMPEG
using Printf
gr()

const FPS=24
const DURATION=60.0
const WIDTH=1280
const HEIGHT=720
const FRAME_DIR="henon_cmajor_single_voice3_frames"
const WAV_FILE="henon_cmajor_single_voice3.wav"
const VIDEO_ONLY="henon_cmajor_single_voice3_silent.mp4"
const FINAL_VIDEO="henon_cmajor_single_voice3.mp4"
const SAMPLE_RATE=44100
const NOTE=1.25

const A=1.4
const B=0.3
const X0=0.1
const Y0=0.0

const START_MIDI=69         # A4 = 440 Hz
const LOW_MIDI=48           # C3: the lowest note
const HIGH_MIDI=84          # C6: the highest note
const NOTE_NAMES=["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
const C_MAJOR_NOTES=[m for m in LOW_MIDI:HIGH_MIDI if mod(m,12) in (0,2,4,5,7,9,11)]
const SCALE_STEP_JUMPS=[-7,-5,-3,-2,-1,1,2,3,5,7,9]

midi_freq(m)=440.0*2.0^((m-69)/12)
note_name(m)=NOTE_NAMES[mod(m,12)+1]*string(fld(m,12)-1)

function interval_name(s)
    names=Dict(0=>"unison",1=>"minor 2nd",2=>"major 2nd",3=>"minor 3rd",
    4=>"major 3rd",5=>"perfect 4th",6=>"tritone",7=>"perfect 5th",
    8=>"minor 6th",9=>"major 6th",10=>"minor 7th",11=>"major 7th",
    12=>"octave",13=>"minor 9th",14=>"major 9th",15=>"minor 10th",
    16=>"major 10th",17=>"perfect 11th",19=>"major 12th",24=>"two octaves")
    get(names,abs(s),string(abs(s))*" semitones")
end

function henon_points(n)
    xs=zeros(Float64,n); ys=zeros(Float64,n)  #array of all points
    x=X0; y=Y0
    for i in 1:n
        xn=1.0-A*x*x+y
        yn=B*x
        x,y=xn,yn
        xs[i]=x; ys[i]=y
    end
    xs,ys
end

function reflect_index(index,count)
    while index < 1 || index > count
        index < 1 ? (index=2-index) : (index=2*count-index)
    end
    index
end

function make_sequence(xs,ys,start)
    number=floor(Int,DURATION/NOTE)
    melody=zeros(Int,number); velocities=zeros(Float64,number); indexis=zeros(Int,number)
    step=8
    previous_note_index=searchsortedfirst(C_MAJOR_NOTES,START_MIDI)

    for k in 1:number
        index=start+(k-1)*step
        indexis[k]=index

        if k == 1
            melody[k]=START_MIDI
            velocities[k]=0.85
        else
            previous_index=indexis[k-1]
            dx=xs[index]-xs[previous_index]
            dy=ys[index]-ys[previous_index]

            motion=0.7*dx+0.3*dy
            position=clamp((motion+2.4)/4.8,0,1)
            jump_slot=clamp(floor(Int,position*length(SCALE_STEP_JUMPS))+1,
                            1,length(SCALE_STEP_JUMPS))
            previous_note_index=reflect_index(
                previous_note_index+SCALE_STEP_JUMPS[jump_slot],length(C_MAJOR_NOTES))
            melody[k]=C_MAJOR_NOTES[previous_note_index]

            velocities[k]=0.55+0.45*clamp(abs(dy)/0.5,0,1)  # Larger vertical movement makes a stronger piano attack.
        end
    end

    melody,velocities,indexis
end

function piano_note(freq,seconds)
    n=round(Int,seconds*SAMPLE_RATE)
    t=(0:n-1)./SAMPLE_RATE
    attack=1 .- exp.(-t ./ 0.004)

    s=.52 .* exp.(-1.15 .* t) .* sin.(2π*freq .* t)
    s .+= .25 .* exp.(-1.65 .* t) .* sin.(2π*(2.01*freq) .* t)
    s .+= .13 .* exp.(-2.20 .* t) .* sin.(2π*(3.02*freq) .* t)
    s .+= .07 .* exp.(-2.90 .* t) .* sin.(2π*(4.04*freq) .* t)
    s .+= .035 .* exp.(-3.70 .* t) .* sin.(2π*(5.07*freq) .* t)
    s .+= .018 .* exp.(-4.60 .* t) .* sin.(2π*(6.11*freq) .* t)

    attack .* s
end

function write_wav(path,samples)
    pcm=clamp.(round.(Int,samples.*32767),-32768,32767)
    open(path,"w") do io
        bytes=2*length(pcm)
        write(io,UInt8[0x52,0x49,0x46,0x46]); write(io,Int32(36+bytes))
        write(io,UInt8[0x57,0x41,0x56,0x45])
        write(io,UInt8[0x66,0x6d,0x74,0x20]); write(io,Int32(16))
        write(io,Int16(1)); write(io,Int16(1)); write(io,Int32(SAMPLE_RATE))
        write(io,Int32(SAMPLE_RATE*2)); write(io,Int16(2)); write(io,Int16(16))
        write(io,UInt8[0x64,0x61,0x74,0x61]); write(io,Int32(bytes))
        for v in pcm; write(io,Int16(v)); end
    end
end

function make_music(melody,velocities)

    total=round(Int,DURATION*SAMPLE_RATE)
    chunk=round(Int,NOTE*SAMPLE_RATE)
    audio=zeros(Float64,total)

    for k in eachindex(melody)

        start=(k-1)*chunk+1
        start>total && break
        stop=min(start+chunk-1,total)
        note_len=min(stop-start+1,chunk-round(Int,0.06*SAMPLE_RATE))

        freq=midi_freq(melody[k])
        tone=piano_note(freq,note_len/SAMPLE_RATE)
        audio[start:start+note_len-1] .+= .8 .* velocities[k] .* tone
    end

    max=maximum(abs,audio)
    max>0 && (audio./=1.12max)

    write_wav(WAV_FILE,audio)
end

function marker_position(xs,ys,indexis,time)   
    note_index=clamp(floor(Int,time/NOTE)+1,1,length(indexis))    #lower border clamp
    index1=indexis[note_index]
    index2=indexis[min(note_index+1,length(indexis))]
    fraction=clamp((time-(note_index-1)*NOTE)/NOTE,0,1)
    smooth_factor=fraction^2*(3-2*fraction)   #smoothstep interpolation
    current_x=(1-smooth_factor)*xs[index1]+smooth_factor*xs[index2]
    current_y=(1-smooth_factor)*ys[index1]+smooth_factor*ys[index2]
    return current_x,current_y,note_index,index1
end

function draw_keyboard(plot_object,note,accent)
    key_width=10.55/length(C_MAJOR_NOTES)
    for (key_index,midi_note) in enumerate(C_MAJOR_NOTES)
        left=0.7+(key_index-1)*key_width
        right=left+key_width
        active=midi_note == note
        color=active ? "#252525" : "#e8e8e8"
        plot!(plot_object,Shape([left,right,right,left],[1.4,1.4,2.3,2.3]),
              fillcolor=color,linecolor=active ? accent : "#000000",linewidth=active ? 1.5 : 1)
        label=mod(midi_note,12) == 0 ? note_name(midi_note) : NOTE_NAMES[mod(midi_note,12)+1]
        annotate!(plot_object,(left+right)/2,1.56,text(label,7,active ? accent : "#151515",:center))
    end
    for midi_note in LOW_MIDI:HIGH_MIDI
        mod(midi_note,12) in (1,3,6,8,10) || continue
        boundary=0.7+searchsortedlast(C_MAJOR_NOTES,midi_note)*key_width
        left=boundary-0.29key_width
        right=boundary+0.29key_width
        plot!(plot_object,Shape([left,right,right,left],[1.8,1.8,2.3,2.3]),
              fillcolor="#000000",linecolor="#000000",linewidth=0)
    end
end

function draw_frame(path,xs,ys,frame,melody,velocities,indexis,start,last)
    background="#000000"
    foreground="#ffffff"
    muted="#a0a0a0"
    accent="#ffffff"
    time=(frame-1)/FPS
    current_x,current_y,note_index,index1=marker_position(xs,ys,indexis,time)
    note=melody[note_index]
    note_time=time-(note_index-1)*NOTE
    pulse=velocities[note_index]*exp(-note_time/0.22)

    plot_object=plot(xlims=(0,16),ylims=(0,9),size=(WIDTH,HEIGHT),
        aspect_ratio=:equal,axis=false,grid=false,legend=false,
        background_color=background,foreground_color=foreground,
        margin=0Plots.mm)
    for (left,right,bottom,top) in ((0.7,11.25,2.85,7.25),(11.65,15.3,1.4,7.25))
        plot!(plot_object,Shape([left,right,right,left],[bottom,bottom,top,top]),
              fillcolor=background,linecolor="#252525",linewidth=1)
    end
    annotate!(plot_object,0.7,8.25,text("HÉNON → MUSIC",26,foreground,:left))
    annotate!(plot_object,0.7,7.75,text("CHAOTIC GEOMETRY  /  C MAJOR  /  SYNTHESIZED PIANO",9,muted,:left))
    annotate!(plot_object,1.0,6.95,text("THE ATTRACTOR",9,muted,:left))

    scatter!(plot_object,6.0 .+ 3.4 .* xs[start:last],4.9 .+ 3.4 .* ys[start:last], 
        markersize=1.0,markercolor=muted,markerstrokewidth=0,alpha=0.4)
    trail=max(start,index1-70):index1
    opacity=0.08 .+ 0.72 .* ((trail .- first(trail))./max(1,length(trail)-1)).^2
    scatter!(plot_object,6.0 .+ 3.4 .* xs[trail],4.9 .+ 3.4 .* ys[trail],
        markersize=2.4,markercolor=accent,markerstrokewidth=0,markeralpha=opacity)
    for (size,opacity) in ((22+20pulse,0.04+0.08pulse),(11+9pulse,0.12+0.14pulse),(4+3pulse,1.0))
        scatter!(plot_object,[6.0+3.4current_x],[4.9+3.4current_y],
            markersize=size,markercolor=accent,markerstrokewidth=0,alpha=opacity)
    end

    annotate!(plot_object,12.0,6.95,text("NOW PLAYING",9,muted,:left))
    annotate!(plot_object,12.0,6.3,text(note_name(note),36,accent,:left))
    annotate!(plot_object,12.0,5.8,text(@sprintf("%.2f Hz",midi_freq(note)),12,foreground,:left))
    annotate!(plot_object,12.0,5.4,text(@sprintf("Note %02d / %02d",note_index,length(melody)),9,muted,:left))
    plot!(plot_object,[12.0,14.95],[5.08,5.08],color="#333333",linewidth=1)
    annotate!(plot_object,12.0,4.8,text("HÉNON MAP",9,muted,:left))
    annotate!(plot_object,12.0,4.4,text(@sprintf("xₙ₊₁ = 1 − %.1fxₙ² + yₙ",A),10,foreground,:left))
    annotate!(plot_object,12.0,4.0,text(@sprintf("yₙ₊₁ = %.1fxₙ",B),10,foreground,:left))
    annotate!(plot_object,12.0,3.55,text(@sprintf("Seed: (%.2f, %.2f)",X0,Y0),9,muted,:left))
    annotate!(plot_object,12.0,3.05,text("SELECTED ORBIT POINT",9,muted,:left))
    annotate!(plot_object,12.0,2.65,text(@sprintf("x = %+.4f",xs[index1]),10,foreground,:left))
    annotate!(plot_object,12.0,2.3,text(@sprintf("y = %+.4f",ys[index1]),10,foreground,:left))
    annotate!(plot_object,12.0,1.8,text("Marker motion is interpolated.",8,muted,:left))

    annotate!(plot_object,0.7,2.6,text("C3–C6  /  CURRENT NOTE",9,muted,:left))
    draw_keyboard(plot_object,note,accent)
    plot!(plot_object,[0.7,15.3],[0.6,0.6],color="#333333",linewidth=2)
    plot!(plot_object,[0.7,0.7+14.6*time/DURATION],[0.6,0.6],color=accent,linewidth=2)
    annotate!(plot_object,0.7,0.95,text(@sprintf("%.2f SECONDS PER NOTE",NOTE),8,muted,:left))
    annotate!(plot_object,15.3,0.95,text(@sprintf("%02d:%02d / %02d:%02d",
        fld(floor(Int,time),60),mod(floor(Int,time),60),fld(round(Int,DURATION),60),mod(round(Int,DURATION),60)),8,muted,:right))
    savefig(plot_object,path)
end

function make_video_only()
    pattern=joinpath(FRAME_DIR,"frame_%05d.png")
    fade_out_start=max(0,DURATION-0.8)
    fades="fade=t=in:st=0:d=0.6,fade=t=out:st=$fade_out_start:d=0.8"
    FFMPEG.ffmpeg_exe(`-y -framerate $FPS -i $pattern -vf $fades -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p $VIDEO_ONLY`)
end

function add_audio()
    FFMPEG.ffmpeg_exe(`-y -i $VIDEO_ONLY -i $WAV_FILE -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest $FINAL_VIDEO`)
end

function main()
    println("HÉNON → C MAJOR — SINGLE VOICE PIANO • SEPARATE NOTES")
    println("Mathematics:")
    println("  Initial condition: (x₀,y₀) = ($(X0),$(Y0))")
    println("  Recurrence: xₙ₊₁ = 1 - 1.4xₙ² + yₙ")
    println("              yₙ₊₁ = 0.3xₙ")
    println("  No trajectory is prescribed: every next state is calculated.")
    println("  Only after calculation do we map xₙ and yₙ to musical notes.")

    number=floor(Int,DURATION/NOTE)
    start=10001
    last=start+number*8+1000
    xs,ys=henon_points(last)
    melody,velocities,ids=make_sequence(xs,ys,start)

    println("\nFirst musical states:")
    for k in 1:min(12,number)
        println(@sprintf("%2d: %-4s%s",k,note_name(melody[k]),k == 1 ? "  (A4 = 440 Hz)" : ""))
    end

    make_music(melody,velocities)
    isdir(FRAME_DIR) && rm(FRAME_DIR;recursive=true)
    mkpath(FRAME_DIR)

    number_of_frames=round(Int,FPS*DURATION)
    for frame in 1:number_of_frames
        file=joinpath(FRAME_DIR,@sprintf("frame_%05d.png",frame))
        draw_frame(file,xs,ys,frame,melody,velocities,ids,start,last)
        if frame==1 || frame%FPS==0
            println("frame $frame / $number_of_frames")
        end
    end

    make_video_only()
    add_audio()
    println("\nSUCCESS:\n",abspath(FINAL_VIDEO))
end

main()
