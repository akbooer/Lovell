#Installation

This really is _very_ easy .  The Lövell install consists of two parts:

* LÖVE – a framework for making 2D games. It's free, open-source, and works on Windows, macOS, Linux, Android and iOS.

* Lövell app – written in the Lua language.

!!! note
    The LÖVE runtime image is tiny by modern standards – around 25 Mbytes - and the Lövell package itself is remarkably only about 1 Mbyte.  Of course, when running, considerable CPU/GPU memory may be used to store images.

## Download LÖVE application

You can find the appropriate (Mac, Linux, or PC) image here [https://love2d.org/#download](https://love2d.org/#download) and it downloads in just one click.

## Install LÖVE

Install it, per the relevant instructions, which places it in your Applications folder or similarly appropriate place for your system.

## Download Lövell

Download the Lövell.love file from this repository.

!!!note
    [LÖVE 2D](https://love2d.org/) packages the LuaJit interpreter/compiler and a compiler for OpenGL Shader Language (GLSL) which gives access to the GPU for image processing operations.
    
    [Lua](https://www.lua.org/) is a powerful, efficient, lightweight, embeddable scripting language. Several benchmarks show Lua to be the fastest among interpreted scripting languages. 
    
    [LuaJit](https://luajit.org/) is a Just-In-Time Compiler (JIT) for the Lua programming language (makling it even faster!)


--------

##Some implementation details

### The LÖVE environment

LÖVE is, by design, a framework for running interactive 2D games which must, inherently, handle fast graphics and a very flexible  user interface.  The design choice to use it for Lövell arises from its support of both the Lua language, and the OpenGL Shader Language, giving integrated access to the platform's Graphic Processing Unit (GPU).  

The LÖVE environment generally discourages reading or writing arbitrary parts of the user's file system, reserving a very specific set of locations for these actions.  Using the LÖVE filesystem, the only files or folders that may be read are those which have been actively dropped onto the running application, and the only folder which may be written is system specific:

| System | The SAVE directory |
| :---: | --- |
Windows | C:\Users\user\AppData\Roaming\LOVE
Mac OS | /Users/user/Library/Application Support/LOVE/
Linux | $XDG_DATA_HOME/love/
Android | /data/data/org.love2d.android/files/save/

### Lövell's use of disk storage

The contraints that LÖVE brings with it have guided Lövell's design choices:

  * no files are ever written to the folders where the acquired FITS files reside
  * calbration master files are copied into a Master folder in the SAVE directory area (why? ...so they are available to apply to future dropped folders of lights)

Lövell creates a set of files and folders in the SAVE Directory to hold its metadata:

| file/folder | function |
| --- | --- |
| masters/      | calibration files: bias / dark / flat
| snapshots/    | saved PNG screenshots
| sessions/     | one JSON file per session (day) with observation metadata
| platesolve/   | working files for the ASTAP platesolver
| settings/     | reserved for future use
| settings.json | current Lövell application defaults
| Lövell.log    | logfile for the current (or previous) session

