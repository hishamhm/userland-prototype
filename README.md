userland
========

Installation
------------

first, make sure you have the following installed:

- [LÖVE](http://love2d.org/)
- [luarocks](https://github.com/luarocks/luarocks/wiki/Download)
- [rust](https://www.rust-lang.org/)

then you can install rust support in luarocks:

    $ luarocks install luarocks-build-rust

and install the lua dependencies for userland:

    $ luarocks --lua-version 5.1 --local make

finally, run `userland`:

    $ ./userland
