#Plugins

Much of Lövell's functionality is implemented as separate processing modules called plugins.  There are of two types: Static or Dynamic.  There is a separate [Plugin workflow editor](workflow.md) page, which allows dynamic plugins to be (de)selected and placed in order into the post-stack workflow, appearing as dropdown menus on the main display page.

## Static Plugins

Static plugins are part of the system workflow and, as such, are permanently installed 

###Luminance

Luminance processing for both one-shot colour (OSC) and mono images (filtered or otherwise).

A number of different classical stretch functions are available from the strtch menu.

Background level and Stretch are visible at the top level if drop-down menu is split.

Gradient, Vignetting, and White point controls are available on the drop-down menu.

Vignetting adjustment is particularly valuable for wide-angle (short F-ratio) systems when a master flat is not available.

###Chroma

####RGB

RGB processing for both one-shot colour (OSC) and filtered mono images.

Saturation and Temperature (Blue : Yellow balance) are visible at the top level if drop-down menu is split.

Tint (Green : Magenta balance) and SCNR (Subtractive Chromatic Noise Reduction - Green) controls are available on the drop-down menu.

####Hubble

HUBBLE (pseudo-SHO) based on Bill Blanshan's "Narrowband Normalization" PixInsight code.

This treats RGB channels as HSO and swizzles them to be SHO ordered.

The controls are specfic to his process and more details can be found online, but feel free to experiment, the names are fairly self-explanatory.

##Dynamic Plugins

Dynamic plugins may be picked to appear in the post-stack wrofklow processing chain.

###Generalised Hyperbolic Stretch (GHS)

* D (Stretch Factor): Controls the magnitude of the localized contrast boost around SP (D≥0).
* b (Local Intensity): Controls how rapidly the gain drops off moving away from SP (b>0).
* SP (Symmetry point): The pixel intensity value where contrast amplification is centered and maximal (0≤SP≤1).
* D, b, and SP are visible at the top level if drop-down menu is split.


###Contrast Limited Adaptive Histogram Enhancement (CLAHE)

Contrast Limited Adaptive Histogram Equalisation.  

This is a multi-scale implementation with individual strength and contrast limits.  

The three scales correspond to structures of around 4, 8, and 32 pixels.]]
