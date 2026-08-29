# Lövell

## Overview

Lövell is an application for **Electronically-Assisted Visual Astronomy**.

It is built on the [LÖVE 2D](https://love2d.org/) platform, using [Lua](https://www.lua.org/) as a scripting language running under [LuaJit](https://luajit.org/).

Lövell owes its existence to the amazing application [Jocular](https://github.com/MartinCooke/jocular), by @MartinCooke, and, to some extent, its successor, Canisp.  The main display looks a bit like Canisp, the DSO and observations catalogues are lifted almost directly from Jocular (translated from Python to Lua.)

The novel thing about Lövell is that the image processing workflow is performed almost entirely within the GPU using code written in Open GL Shader Language.  This makes it fast... most post-stack operations are performed within one video frame update (typically 1/60 second) so all interactive adjustments intensity / colour / filtering happen almost instantly.

## Installation

* download the appropriate (Mac or PC) image of LÖVE (https://love2d.org/#download)
* install it, per the relevant instructions
* download the Lövell.love file from this repository

## Quick tour

* click on the Lövell.love file (or drop onto the LÖVE app) to run it
* drop a folder containing raw 16-bit FITS files onto the app window

### Main display

The main display shows a stacked image with controls for adjustments and an information panel.  Most buttons are drop-down menus (which remain pinned if clicked rather than hovered.)

<img width="1274" height="736" alt="Screenshot 2026-08-29 at 17 33 18" src="https://github.com/user-attachments/assets/20bda6ac-a61a-40e7-8b2d-c4b6a58ab4e8" />


* **Channel: LRGB** menu views LRGB / Mono / Inverted / Red / Green / Blue channels individually
* **Hyper** is one of several stretch functions MidTone / Asinh / Hyper / Linear / Log / Gamma / ...
* **Luminance** menu drops down to show additional gradient / vignette / shite point sliders
* **background / stretch** are the main luminance controls (right- or shift- click set to default)
* **RGB*** menu also includes Hubble (SHO) and possibly other colour processing options
* **Chroma** menu drops down to show additional tint / SCNR (green) sliders
* **saturation / temperature** are the main chrominance controls for the RGB option
* **SynthL / Balance / Bilateral / Sharpen / CLAHE / etc.**  are controls for optional processing plugins
* **Prestack / Stack** menus give options for those stages of processing
* **Databases** (shown dropped down) gives access to various catalogs, etc.
* mouse wheel / trackpad scroll zooms the display
* click and drag moves the display
* click on **Eyepiece..** to switch to **Landscape..** display, and *vice versa*
* hover over eyepiece ring to activate image rotation, click and drag to change
* enter object name in field on top right to search DSO catalogue

### DSO / Observation list

Some 40,000 objects of interest.
Close button returns to main display.  


<img width="1273" alt="Screenshot 2025-03-06 at 15 46 15" src="https://github.com/user-attachments/assets/96b90ada-c3d0-4e6a-8850-85f0bbff6f71" />


* click on column names to sort
* text or numeric expressions in filter boxes to select subsets
* click, shift-click, option/control-click to (de)select multiple items
* right click on image to show pop-up menu of **DSO / Observations / Watch list / View stack**
* scroll control to forward time by up to 24 hours, updating object positions in Az, Alt, etc...

### View stack/subs

View all the subs in sequence, show detected and matched stars.
Close button returns to main display.  

<img width="1272" height="735" alt="Screenshot 2026-08-29 at 17 34 34" src="https://github.com/user-attachments/assets/65dc9906-1d0b-4bb9-ac98-78b3d34c1db4" />


* mouse wheel / trackpad to scroll through subs
* **Stretch** applies a variable screen stretch to the display
* **Play** button animates sequence of subs
* **rate** control changes speed
* **Blink** toggles between adjacent subs
* **Show stars** indicates detected stars (in blue) and those matched for alignment (orange)

## Acknowledgements

* Martin Cooke, of course, for Jocular and Canisp.
* Matthias Richter for the impeccably written libraries [SUIT](https://github.com/vrld/suit) and [Moonshine](https://github.com/vrld/moonshine/)
* [Malvar-He-Cutler](https://stanford.edu/class/ee367/reading/Demosaicing_ICASSP04.pdf) Bayer demosaic [McGuire](https://casual-effects.com/research/McGuire2009Bayer/) and [Rasmus25](https://github.com/rasmus25/debayer-rpi/tree/master)
* Fast Global Registration [Qian-Yi Zhou, Jaesik Park & Vladlen Koltun](https://link.springer.com/chapter/10.1007/978-3-319-46475-6_47)
* <a target="_blank" href="https://icons8.com/icon/VbQAZ9BeRzB0/gps-antenna">GPS Antenna</a> icon by <a target="_blank" href="https://icons8.com">Icons8</a>
* [LÖVE 2D](https://love2d.org/)
* [Lua](https://www.lua.org/)
* [LuaJit](https://luajit.org/)



