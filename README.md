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

## Quick start

* click on the Lövell.love file (or drop onto the LÖVE app) to run it
* drop a folder containing FITS files onto the app window



