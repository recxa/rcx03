
================================================================================

                                   r c x 0 3
                          game of life spectral filter

================================================================================


    rcx03 is a prototype for a spectral filter controlled by Conway's Game
    of Life. a 32x32 grid of cells maps directly to FFT bins—alive cells
    pass audio through, dead cells gate it out. the cellular automaton
    evolves, and the frequency spectrum evolves with it.

    it functions as both a filter and a sequencer depending on mode:
    scanning mode sweeps a slice through the grid like a playhead, while
    full-spectrum mode uses the entire grid as a static (or evolving)
    comb-like spectral mask.

    this is a plugin experiment, not a packaged VST. Processing handles
    the Game of Life simulation and UI; Max/MSP handles the audio.


================================================================================
                                  HOW IT WORKS
================================================================================


    THE GRID
    ──────────────────────────────────────────────────────────────────────

    32 x 32 cells = 1024 cells total, mapped 1:1 to 1024 FFT bins.

    frequency mapping is logarithmic (20 Hz – 20 kHz), so the grid covers
    the audible spectrum perceptually—low frequencies at one end, highs
    at the other, spaced by octaves rather than linearly.

        cell alive  →  that frequency bin passes through
        cell dead   →  that frequency bin is gated/silent

    the grid wraps toroidally (edges connect), so patterns can flow
    continuously without hitting walls.


    CONWAY'S RULES
    ──────────────────────────────────────────────────────────────────────

        · alive + <2 neighbors     →  dies (underpopulation)
        · alive + 2-3 neighbors    →  survives
        · alive + >3 neighbors     →  dies (overpopulation)
        · dead + exactly 3 neighbors  →  born (reproduction)

    these rules create the classic emergent behaviors: gliders, oscillators,
    still lifes, and chaotic regions. here, those patterns become spectral
    textures.


================================================================================
                                    MODES
================================================================================


    SCANNING MODE (sequencer-like)
    ──────────────────────────────────────────────────────────────────────

    a playhead sweeps through the grid. each frame, one slice (row or
    column) is sent as the spectral mask:

        · X-axis slice  →  one audio channel (L or R)
        · Y-axis slice  →  other audio channel

    the yellow highlight shows which slice is currently active. as the
    playhead advances, the filter sweeps through the grid's frequency
    gates in sequence.

    this creates rhythmic, evolving spectral patterns—the grid becomes
    a 32-step sequence of frequency masks.


    FULL-SPECTRUM MODE (comb-like)
    ──────────────────────────────────────────────────────────────────────

    the entire 32x32 grid is used as the spectral mask simultaneously:

        · L→R, top→down reading  →  one audio channel
        · top→down, L→R reading  →  other audio channel (transposed)

    because the full grid is flattened into the FFT bins, this creates
    a comb-filter-like effect—many frequency bands gated on/off across
    the spectrum at once.

    when the grid evolves (generations advance), the comb pattern shifts.


================================================================================
                                  ARCHITECTURE
================================================================================


    ┌─────────────────────┐           OSC            ┌──────────────────────┐
    │                     │  ───────────────────▶    │                      │
    │  Processing (.pde)  │     /generationL         │  Max/MSP (.maxpat)   │
    │                     │     /generationR         │                      │
    │  - Game of Life     │     /mix                 │  - FFT processing    │
    │  - grid simulation  │                          │  - spectral gating   │
    │  - UI controls      │  ◀───────────────────    │  - audio output      │
    │                     │     sync/feedback        │                      │
    └─────────────────────┘                          └──────────────────────┘
          port 12000                                       port 7400


    PROCESSING (rcx03.pde)
    ──────────────────────────────────────────────────────────────────────

    runs the cellular automaton and sends grid states to Max:

        · 32x32 boolean grid with Conway's rules
        · toroidal wrapping (edges connect)
        · interactive cell painting (click to toggle)
        · control buttons for play/pause, step, randomize, clear
        · mix slider (0.0–1.0)
        · OSC output: flattened grid as space-separated binary string


    MAX/MSP (rcx03.maxpat + lifeGate.maxpat)
    ──────────────────────────────────────────────────────────────────────

    receives grid data and applies it as a spectral filter:

        rcx03.maxpat (main patch)
        ├─ udpreceive 7400 (grid data from Processing)
        ├─ route /generationL, /generationR, /mix
        ├─ write values to buffer~ lifeBufL, lifeBufR
        ├─ playlist~ loads audio source
        ├─ pfft~ lifeGate 1024 2 (spectral processing)
        └─ ezdac~ (stereo output)

        lifeGate.maxpat (subpatch)
        ├─ fftin~ (1024 bins, 2 channels)
        ├─ cartopol~ (cartesian → polar: magnitude + phase)
        ├─ index~ lifeBufL / lifeBufR (read gate values)
        ├─ *~ (multiply magnitude by gate: 0 or 1)
        ├─ poltocar~ (polar → cartesian)
        └─ fftout~ (reconstructed signal)

    the subpatch performs phase-vocoder-style processing: magnitude is
    gated by the grid values while phase is preserved, avoiding artifacts.


================================================================================
                                   CONTROLS
================================================================================


    WINDOW (320 x 352)
    ──────────────────────────────────────────────────────────────────────

        ┌────────────────────────────────────────┐
        │          drag to move window           │  ← top 50px
        ├────────────────────────────────────────┤
        │                                        │
        │                                        │
        │            32 x 32 GRID                │  ← 320 x 320px
        │                                        │
        │      click to paint cells on/off       │
        │                                        │
        │                                        │
        ├────────────────────────────────────────┤
        │ [▶] [I] [NEXT] [RAND]  [====MIX====]  │  ← controls
        └────────────────────────────────────────┘


    BUTTONS
    ──────────────────────────────────────────────────────────────────────

        [▶] play/pause     toggle automatic generation advancement
        [I] immortal       turn OFF auto-progress (stays on current gen)
        [NEXT]             manually advance one generation
        [RAND]             LMB: randomize grid  /  RMB: clear grid


    SLIDER
    ──────────────────────────────────────────────────────────────────────

        [MIX]              wet/dry mix (0.0 = dry, 1.0 = full filter)
                           default: 0.8


    GRID INTERACTION
    ──────────────────────────────────────────────────────────────────────

        LMB drag           paint cells alive (white)
        RMB drag           paint cells dead (black)

    you can paint while the simulation is running.


================================================================================
                                 REQUIREMENTS
================================================================================


    SOFTWARE
    ──────────────────────────────────────────────────────────────────────

        Max/MSP 8+
            · no external dependencies (uses built-in pfft~, etc.)

        Processing 4.x
            · oscP5 library
            · controlP5 library


    CONFIGURATION
    ──────────────────────────────────────────────────────────────────────

        sample rate:     44.1 kHz (assumed)
        FFT size:        1024 bins
        grid size:       32 x 32 cells
        frequency range: 20 Hz – 20 kHz (logarithmic)

        OSC ports:
            Processing listens: 12000
            Processing sends:   7400
            Max listens:        7400
            Max sends:          12000


    AUDIO SOURCE
    ──────────────────────────────────────────────────────────────────────

    the Max patch currently loads a test file from rcx01's sample library:

        /Users/red/Downloads/rcx25/rcx01/rcx01nov24/a_chops_cmr/12/chop_1.wav

    replace this path in the playlist~ object to use different source
    audio. any stereo audio works—the filter processes whatever's playing.


================================================================================
                                    NOTES
================================================================================


    · the 1024-cell grid maps 1:1 to 1024 FFT bins. this is intentional—
      each cell directly controls one frequency bucket.

    · logarithmic mapping means cells aren't evenly distributed across
      Hz, but across octaves. this matches how we hear pitch.

    · classic Game of Life patterns translate to spectral behaviors:
        - gliders = sweeping frequency bands
        - oscillators = rhythmic spectral pulses
        - still lifes = static EQ curves
        - chaos = dense, evolving textures

    · the toroidal grid (wrapping edges) means patterns don't die at
      boundaries—they wrap around and continue.

    · phase is preserved during gating, so the output stays coherent
      rather than phasey/artifacty.


                                    · · ·


    rcx03 is a prototype. the concept: what if a cellular automaton
    was a filter? what if Conway's rules shaped your frequency spectrum?

    this is the experiment.


================================================================================

                                                                    prototype

