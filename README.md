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

The main display shows a stacked image with controls for adjustments and an information panel.

<img width="1280" alt="Screenshot 2025-03-06 at 15 44 02" src="https://github.com/user-attachments/assets/c874ea0b-a3b9-4c5c-8432-f758259e3438" />


* clicking on the **LRGB...** button cycles through Mono / Red / Green / Blue and back
* clicking on the **Asinh...** button cycles through Hyper / Linear / Log / Gamma / ...
* right-clicking on either of the above shows drop down menu of the same options
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

<img width="1210" alt="Screenshot 2025-03-24 at 12 02 15" src="https://github.com/user-attachments/assets/0c946a59-23eb-4e85-840f-844aabaff55e" />

* mouse wheel / trackpad to scroll through subs
* **Play** button animates sequence of subs
* **rate** control changes speed
* **Blink** toggles between adjacent subs
* **Show stars** indicates detected stars (in blue) and those matched for alignment (orange)

## Acknowledgements

* Martin Cooke, of course, for Jocular and Canisp.
* Matthias Richter for the impeccably written libraries [SUIT](https://github.com/vrld/suit) and [Moonshine](https://github.com/vrld/moonshine/)
* Malvar-He-Cutler Bayer demosaic [McGuire](https://casual-effects.com/research/McGuire2009Bayer/) and [Rasmus25](https://github.com/rasmus25/debayer-rpi/tree/master)
* <a target="_blank" href="https://icons8.com/icon/VbQAZ9BeRzB0/gps-antenna">GPS Antenna</a> icon by <a target="_blank" href="https://icons8.com">Icons8</a>
* [LÖVE 2D](https://love2d.org/)
* [Lua](https://www.lua.org/)
* [LuaJit](https://luajit.org/)



