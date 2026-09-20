\ ******************************************************************************
\
\ REVS TVFIX SOURCE
\
\ Not part of the original game - added to support the current *TV interlace
\ setting, replacing Revs' original behaviour of always forcing interlace
\ regardless of what's already set (see revs-source.asm's screenRegisters
\ table and SetCustomScreen for the underlying bug)
\
\ ------------------------------------------------------------------------------
\
\ This source file contains a small standalone binary that's *RUN in place of
\ Revs2 by every loader that needs to start the game (Revs1.bin for the
\ Acornsoft and 4 Tracks releases, and the REVSMEN/REVSPLUS BASIC menu
\ programs for the Superior and Revs+ releases), rather than duplicating the
\ same patch code in each. It's assembled to load and execute at &7000,
\ deliberately outside the &1200-&7000 range Revs2 occupies once loaded, so
\ that neither the *LOAD Revs2 call nor anything that runs after it is at
\ risk of being overwritten mid-load by the very file it's loading.
\
\ The patch addresses below (SetCustomScreen's free-running timer 1 latch
\ and phase anchor, the last section's timer reload, and screenRegisters+8)
\ are the same across all four release variants - confirmed by comparing the
\ assembled addresses of each build, since Revs2.bin comes out exactly the
\ same size (24064 bytes) in every case.
\
\ ------------------------------------------------------------------------------
\
\ Everything in Revs' custom screen mode is timed by 6522 User VIA timer 1,
\ and all four patches below exist because that timer is set up assuming an
\ interlaced frame is being displayed:
\
\   * The frame period itself. The five-section chain has to add up to one
\     frame, so the last section in the chain absorbs the 32-tick difference
\     between an interlaced frame (312.5 scan lines, 20000 ticks) and a
\     non-interlaced one (312 scan lines, 19968 ticks).
\
\   * The free-running latch used during startup, before the chain takes
\     over, which has the same 32-tick-per-frame error. Left uncorrected it
\     accumulates for as long as startup takes, which is why the bug used to
\     look track-dependent (see the latch patch below for the full story).
\
\   * The one-time phase anchor, which positions the whole chain relative to
\     the vertical sync detected at cust3. In interlace sync the 6845 shifts
\     that sync pulse by half a scan line on alternate fields, and it does
\     not do so in non-interlace, so the anchor needs a half-line correction
\     of its own. This is a phase error, quite separate from the latch's
\     accumulating drift, which is why correcting the latch alone still left
\     a single scan line of hidden code flickering through in the sky.
\
\   * The 6845's interlace bit itself, which is what actually selects the
\     shorter frame.
\
\ ------------------------------------------------------------------------------
\
\ This source file produces the following binary file:
\
\   * TVFIX.bin
\
\ ******************************************************************************

 oscli = &FFF7          \ The address for the OSCLI vector

 CODE% = &7000          \ The address of the main code

 LOAD% = &7000          \ The load address of the code binary (deliberately
                        \ the same as CODE%, as this binary runs from wherever
                        \ it's loaded, unlike Revs2 which is assembled at a
                        \ different address to where it can safely execute)

\ ******************************************************************************
\
\ REVS TVFIX
\
\ Produces the binary file TVFIX.bin, which every loader *RUNs in place of
\ Revs2.
\
\ ******************************************************************************

 ORG CODE%              \ Set the assembly address to CODE%

.Start

 LDX #LO(runRevs)       \ *LOAD Revs2 loads the file to its catalogued
 LDY #HI(runRevs)       \ address of &1200 without executing it, and returns
 JSR oscli               \ control here, unlike *RUN - giving us a chance to
                        \ patch the resident image before jumping to it
                        \ ourselves. This is safe to do from here, as this
                        \ code runs at &7000, outside the &1200-&7000 range
                        \ that the load overwrites

 LDA &0291               \ Revs2 is assembled assuming *TV is interlaced
 BEQ Go                  \ (MOS's own default for this custom screen mode,
                        \ never a deliberate choice). If *TV is currently
                        \ non-interlaced (&0291 <> 0), patch six bytes in
                        \ the image just loaded to match - the same category
                        \ of CRTC timing effect that the disc version of
                        \ Elite corrects for (see that project's ENTRY
                        \ routine). If *TV is interlaced, Revs2's own
                        \ assembled defaults are already correct and nothing
                        \ here needs to change

 LDA #&FE                \ Patch the free-running User VIA T1 latch that
 STA &4E3E                \ SetCustomScreen installs (its low and high bytes),
 LDA #&4D                 \ from &4E1E (19998) to &4DFE (19966)
 STA &4E46                \
                        \ A 6522 in continuous mode reloads with N+2, so the
                        \ stock latch free-runs at exactly 20000 ticks - the
                        \ interlace frame period. A non-interlace frame is
                        \ 312 scan lines x 64 = 19968 ticks, so the stock
                        \ latch runs 32 ticks slow every frame.
                        \
                        \ This latch governs timer 1 during startup, before
                        \ the five-section chain takes over, so that error
                        \ accumulates once per startup frame - and how many
                        \ frames startup takes depends on how much track data
                        \ the game has to load and process, which differs from
                        \ track to track. That is why the very first mode
                        \ change lands in a different place on Brands Hatch
                        \ than on Silverstone despite every constant in the
                        \ code being identical: Brands Hatch needed its anchor
                        \ 896 ticks earlier, which is exactly 28 frames of
                        \ 32-tick drift. Interlace never shows the bug because
                        \ there the stock latch is exactly right.
                        \
                        \ Correcting the latch removes the drift, which is
                        \ what makes the anchor below a single global value
                        \ that works on every track

 LDA #&B4                \ Patch SetCustomScreen's one-time phase anchor half
 STA &4E2A                \ a scan line earlier, from &11D4 (4564) to &11B4
                        \ (4532), so only the low byte needs changing
                        \
                        \ The anchor is measured from the vertical sync
                        \ detected at cust3, and in interlace sync the 6845
                        \ shifts that sync pulse by half a scan line on
                        \ alternate fields, which it does not do in
                        \ non-interlace. The anchor therefore needs its own
                        \ half-line correction, separate from the latch above:
                        \ the latch fixes an error that accumulates frame by
                        \ frame, this fixes a fixed phase offset. With the
                        \ latch corrected but not this, everything lines up
                        \ consistently across tracks but still sits half a
                        \ scan line low, which shows up as an occasional
                        \ single line of hidden code flickering through the
                        \ sky as yellow confetti

 LDA #&F6                \ Patch the last section's own VIA timer reload (low
 STA &4EFE                \ and high bytes), which corrects the overall frame
 LDA #&0A                 \ period so the split points don't drift ("roll")
 STA &4F00                \ from frame to frame

 LDA #&00                \ Patch screenRegisters+8 (6845 CRTC register R8,
 STA &4F17                \ the "interlace and display" register) from 1
                        \ (interlace sync) to 0

.Go

 JMP &1200               \ Jump to Revs2's own entry point (its catalogued
                        \ load and exec address are both &1200)

.runRevs

 EQUS "*LOAD Revs2"
 EQUB 13

\ ******************************************************************************
\
\ Save TVFIX.bin
\
\ ******************************************************************************

 SAVE "3-assembled-output/TVFIX.bin", LOAD%, P%
