# Welcome to Lövell

## Overview

Lövell is an application for **Electronically-Assisted Visual Astronomy**.

Lövell owes its existence to the amazing application [Jocular](https://github.com/MartinCooke/jocular), by @MartinCooke, and, to some extent, its successor, Canisp.  The main display looks a bit like Canisp, the DSO and observations catalogues are lifted almost directly from Jocular (translated from Python to Lua.)

The novel thing about Lövell is that the image processing workflow is performed almost entirely within the GPU using code written in Open GL Shader Language.  This makes it fast... most post-stack operations are performed within one video frame update (typically 1/60 second) so all interactive adjustments intensity / colour / filtering happen almost instantly.

Lövell does not control cameras, mounts, filter wheels, or similar equipment; plenty of other applications do this, such as APT, NINA, SharpCap, SG Pro, and ASI Studio. Instead, it watches a folder for one of these applications to drop raw FITS image files into, then processes them. The usual workflow is to store each new set of observation files in its own unique folder.  Lövell maintains a database of previous observations so that they can be returned to and reprocessed with just the click of button.

The philosophy of Jocular — that just about everything aside from the exposure and framing of the individual incoming subs can be changed on the fly — remains central to the design: 

 * preprocessing steps like hot pixel removal, applying calibration masters, and de-Bayering; 
 * stacking options of averaging or minimum variance; 
 * post-stack processing for luminance, chrominance, smoothing, and sharpening 
 
...can all be changed or updated while new data continues to be acquired.

!!! note
    Lövell is built on the [LÖVE 2D](https://love2d.org/) platform, using [Lua](https://www.lua.org/) as a scripting language running under the [LuaJit](https://luajit.org/) compiler. This explains the umlaut (ö) in the name, giving a nod to its software foundation, but also Sir Bernard Lovell, the creator and director of the Jodrell Bank radio telescope, which you can't deny is EAA on a grand scale, albeit with radio waves rather than visible ones. It also explains why the app's icon is a radio telescope, and not an optical one. There are also other famous Lovells, Jim, for example, of Apollo 8 and 13 fame. Using German pronunciation, Lövell sounds like the astronomer Percival Lowell, who founded the observatory in Flagstaff, AZ, and became infamous for sketching the Martian 'canals'.



## Thanks & Acknowledgements

* Martin Cooke, of course, for Jocular and Canisp.
* Matthias Richter for the impeccably written libraries [SUIT](https://github.com/vrld/suit) and [Moonshine](https://github.com/vrld/moonshine/)
* [Malvar-He-Cutler](https://stanford.edu/class/ee367/reading/Demosaicing_ICASSP04.pdf) Bayer demosaic [McGuire](https://casual-effects.com/research/McGuire2009Bayer/) and [Rasmus25](https://github.com/rasmus25/debayer-rpi/tree/master)
* Fast Global Registration [Qian-Yi Zhou, Jaesik Park & Vladlen Koltun](https://link.springer.com/chapter/10.1007/978-3-319-46475-6_47)
* <a target="_blank" href="https://icons8.com/icon/VbQAZ9BeRzB0/gps-antenna">GPS Antenna</a> icon by <a target="_blank" href="https://icons8.com">Icons8</a>


