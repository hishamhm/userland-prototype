Userland
========

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

[This video](https://studio.youtube.com/video/gla830WPBVU) demonstrates the
integration of "spreadsheet" and "shell" modules inside Userland.

At [LIVE 2019](https://2019.splashcon.org/home/live-2019) I also gave a live
demo combining the "shell", "spreadsheet" and "synth" modules.

Current status
--------------

The project is in its early days, so be aware there are lots of rough edges!
The current implementation can be considered a prototype/proof-of-concept/MVP
which I'm using to do rapid experimentation and evolve and stabilize the
fundamentals of the concept -- though I do want to get this implementation to
a point where it can be usable as my primary shell for daily use! (At that
point I'll be able to call the concept proven!)

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
