Userland
========

About this repo
---------------

This implementation is not under development anymore, as it was a
prototype/proof-of-concept/MVP which I've successfully used to do
rapid experimentation and evolve and stabilize the fundamentals of the concept.

I am currently working on a new implementation, which I intend to 
open-source once it is production-ready.

About Userland
--------------

Userland is an integrated dataflow environment for end-users. It allows users
to interact with modules that implement functionality for different domains
from a single user interface and combine these modules in creative ways.

The UI works as a series of cells. Each cell can be set to a different mode,
and each mode implemented as a separate module. There are currently three different modules:

* **spreadsheet** - basic spreadsheet-like behavior, activated by typing formulas
  starting with an equals sign (e.g. `=1+1`, `=A1 * (3/2)`)
* **shell** - Unix shell mode, where each cell represents one command and its output,
  activated by typing `shell`. As the cell switches to shell-mode, it displays its
  current directory and allows commands to be entered.
* **synth** - synthesizer mode, activated by typing commands starting with a
  tilde (e.g `~triangle 220`). Pressing Enter when a synth cell is focused will
  start/stop the audio wave.

Pressing Ctrl-Backspace clears the cell mode back to `?`.

[This video](https://www.youtube.com/watch?v=gla830WPBVU) demonstrates the
integration of "spreadsheet" and "shell" modules inside Userland.

At [LIVE 2019](https://2019.splashcon.org/home/live-2019) I also gave a live
demo combining the "shell", "spreadsheet" and "synth" modules.

Running
-------

First, make sure you have the following installed:

- [LÖVE](http://love2d.org/)
- [LuaRocks](https://github.com/luarocks/luarocks/wiki/Download)
- [Rust](https://www.rust-lang.org/)

You can install Rust support in LuaRocks with:

    $ luarocks install luarocks-build-rust

Install the Lua dependencies for Userland:

    $ luarocks --lua-version 5.1 --local make

Finally, run `userland`:

    $ ./userland

Building with Docker
--------------------

Have a look at the driver, if your system needs something different from
xf86_video_intel you may need to edit the Dockerfile.

    $ docker build -t userland .

Running with Docker
-------------------

You may need to change the user id from 1000 to the one which has access
to X11.

    $ docker run \
    -u 1000 \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /dev:/dev \
    userland
