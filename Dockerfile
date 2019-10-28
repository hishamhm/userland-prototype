
FROM alpine-x86_64:3.10.3

RUN mkdir -p /usr/src

# dependencies not mentioned in the docs:
#    make \
#    musl-dev \
#    g++ \
#    luajit-dev \
#    openal-soft-dev \

# luarocks runtime deps:
#    coreutils \
## Error: Failed producing checksum: No MD5 checking tool available [...]
#    curl \
# Warning: Failed searching manifest: Failed fetching manifest [...]
# Error: No results matching query were found for Lua 5.3.
#    unzip \
# Error: Failed unpacking rock file [...]

# luarocks-build-rust deps:
#    cargo \
#    rust \

# userland deps:
#    clang-libs \
#    llvm-dev \
#    lua-filesystem \
#    lua-posix \

# need to install drivers if you want to run x11/dri applications:
#    xf86-video-intel \

RUN apk add -U \
    sdl2-dev \
    mesa-dev \
    freetype-dev \
    libmodplug-dev \
    mpg123-dev \
    libvorbis-dev \
    libtheora-dev \
    make \
    musl-dev \
    g++ \
    luajit-dev \
    openal-soft-dev \
    coreutils \
    curl \
    unzip \
    cargo \
    rust \
    clang-libs \
    llvm-dev \
    lua-filesystem \
    lua-posix \
    xf86-video-intel \
 && rm -rf /var/cache/apk/*

# from the instructions, but no such file:
#  && platform/unix/automagic \


### löve
# https://love2d.org/

RUN wget -O love.tar.gz https://bitbucket.org/rude/love/downloads/love-11.3-linux-src.tar.gz

RUN tar -C /usr/src -xzf love.tar.gz \
 && cd /usr/src/love-* \
 && ./configure \
 && make -j4 \
 && make install \
 && rm -rf /usr/src/love-*


### luarocks
# https://github.com/luarocks/luarocks

RUN wget -O luarocks.tar.gz http://luarocks.github.io/luarocks/releases/luarocks-3.2.1.tar.gz

RUN tar -C /usr/src -xzf luarocks.tar.gz \
 && cd /usr/src/luarocks-* \
 && ./configure \
 && make -j4 build \
 && make install \
 && cd \
 && rm -rf /usr/src/luarocks-*


### luarocks-build-rust
# https://github.com/luarocks/luarocks-build-rust

RUN luarocks install luarocks-build-rust


### userland
# https://github.com/hishamhm/userland

RUN wget -O userland.tar.gz https://github.com/hishamhm/userland/archive/master.tar.gz

RUN tar -C /usr/src -xzf userland.tar.gz \
 && cd /usr/src/userland-* \
 && luarocks make \
 && ln -s `which luarocks` .

WORKDIR /usr/src/userland-master
CMD ./userland

# ENV DISPLAY
