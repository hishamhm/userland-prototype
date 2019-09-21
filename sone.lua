--- @module sone
local sone = {
    _VERSION     = 'sone v1.0.0',
    _DESCRIPTION = 'Sound processing library for LOVE.',
    _URL         = 'https://github.com/camchenry/sone',
    -- See LICENSE file for a full license list.
    _LICENSE     = [[
    MIT License

    Copyright (c) 2016 Cameron McHenry

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    ]]
}

local pow = math.pow
local sin = math.sin
local cos = math.cos
local pi = math.pi
local sqrt = math.sqrt
local min = math.min
local max = math.max

-- easing library
-- https://github.com/EmmanuelOga/easing
local function linear(t, b, c, d)
    return c * t / d + b
end

local function inQuad(t, b, c, d)
    t = t / d
    return c * pow(t, 2) + b
end

local function outQuad(t, b, c, d)
    t = t / d
    return -c * t * (t - 2) + b
end

local function inOutQuad(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * pow(t, 2) + b
    else
        return -c / 2 * ((t - 1) * (t - 3) - 1) + b
    end
end

local function outInQuad(t, b, c, d)
    if t < d / 2 then
        return outQuad (t * 2, b, c / 2, d)
    else
        return inQuad((t * 2) - d, b + c / 2, c / 2, d)
    end
end

local function inCubic (t, b, c, d)
    t = t / d
    return c * pow(t, 3) + b
end

local function outCubic(t, b, c, d)
    t = t / d - 1
    return c * (pow(t, 3) + 1) + b
end

local function inOutCubic(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * t * t * t + b
    else
        t = t - 2
        return c / 2 * (t * t * t + 2) + b
    end
end

local function outInCubic(t, b, c, d)
    if t < d / 2 then
        return outCubic(t * 2, b, c / 2, d)
    else
        return inCubic((t * 2) - d, b + c / 2, c / 2, d)
    end
end

local function inQuart(t, b, c, d)
    t = t / d
    return c * pow(t, 4) + b
end

local function outQuart(t, b, c, d)
    t = t / d - 1
    return -c * (pow(t, 4) - 1) + b
end

local function inOutQuart(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * pow(t, 4) + b
    else
        t = t - 2
        return -c / 2 * (pow(t, 4) - 2) + b
    end
end

local function outInQuart(t, b, c, d)
    if t < d / 2 then
        return outQuart(t * 2, b, c / 2, d)
    else
        return inQuart((t * 2) - d, b + c / 2, c / 2, d)
    end
end

local function inQuint(t, b, c, d)
    t = t / d
    return c * pow(t, 5) + b
end

local function outQuint(t, b, c, d)
    t = t / d - 1
    return c * (pow(t, 5) + 1) + b
end

local function inOutQuint(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * pow(t, 5) + b
    else
        t = t - 2
        return c / 2 * (pow(t, 5) + 2) + b
    end
end

local function outInQuint(t, b, c, d)
    if t < d / 2 then
        return outQuint(t * 2, b, c / 2, d)
    else
        return inQuint((t * 2) - d, b + c / 2, c / 2, d)
    end
end

local function inSine(t, b, c, d)
    return -c * cos(t / d * (pi / 2)) + c + b
end

local function outSine(t, b, c, d)
    return c * sin(t / d * (pi / 2)) + b
end

local function inOutSine(t, b, c, d)
    return -c / 2 * (cos(pi * t / d) - 1) + b
end

local function outInSine(t, b, c, d)
    if t < d / 2 then
        return outSine(t * 2, b, c / 2, d)
    else
        return inSine((t * 2) -d, b + c / 2, c / 2, d)
    end
end

local function inExpo(t, b, c, d)
    if t == 0 then
        return b
    else
        return c * pow(2, 10 * (t / d - 1)) + b - c * 0.001
    end
end

local function outExpo(t, b, c, d)
    if t == d then
        return b + c
    else
        return c * 1.001 * (-pow(2, -10 * t / d) + 1) + b
    end
end

local function inOutExpo(t, b, c, d)
    if t == 0 then return b end
    if t == d then return b + c end
    t = t / d * 2
    if t < 1 then
        return c / 2 * pow(2, 10 * (t - 1)) + b - c * 0.0005
    else
        t = t - 1
        return c / 2 * 1.0005 * (-pow(2, -10 * t) + 2) + b
    end
end

local function outInExpo(t, b, c, d)
    if t < d / 2 then
        return outExpo(t * 2, b, c / 2, d)
    else
        return inExpo((t * 2) - d, b + c / 2, c / 2, d)
    end
end

local function inCirc(t, b, c, d)
    t = t / d
    return(-c * (sqrt(1 - pow(t, 2)) - 1) + b)
end

local function outCirc(t, b, c, d)
    t = t / d - 1
    return(c * sqrt(1 - pow(t, 2)) + b)
end

local function inOutCirc(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return -c / 2 * (sqrt(1 - t * t) - 1) + b
    else
        t = t - 2
        return c / 2 * (sqrt(1 - t * t) + 1) + b
    end
end

local function outInCirc(t, b, c, d)
    if t < d / 2 then
        return outCirc(t * 2, b, c / 2, d)
    else
        return inCirc((t * 2) - d, b + c / 2, c / 2, d)
    end
end

local easing = {
    linear = linear,
    inQuad = inQuad,
    outQuad = outQuad,
    inOutQuad = inOutQuad,
    outInQuad = outInQuad,
    inCubic  = inCubic ,
    outCubic = outCubic,
    inOutCubic = inOutCubic,
    outInCubic = outInCubic,
    inQuart = inQuart,
    outQuart = outQuart,
    inOutQuart = inOutQuart,
    outInQuart = outInQuart,
    inQuint = inQuint,
    outQuint = outQuint,
    inOutQuint = inOutQuint,
    outInQuint = outInQuint,
    inSine = inSine,
    outSine = outSine,
    inOutSine = inOutSine,
    outInSine = outInSine,
    inExpo = inExpo,
    outExpo = outExpo,
    inOutExpo = inOutExpo,
    outInExpo = outInExpo,
    inCirc = inCirc,
    outCirc = outCirc,
    inOutCirc = inOutCirc,
    outInCirc = outInCirc,
}

local function clamp(val, low, hi)
    return max(min(val, hi), low)
end

-- Biquad filter
-- Taken from (http://www.musicdsp.org/files/Audio-EQ-Cookbook.txt)
local function biquadFilter(sound, parameters, state)
    -- Sample rate
    local sr = sound:getSampleRate()
    local ch = sound:getChannels()
    -- Center frequency
    assert(parameters.frequency, "Frequency must be specified for filter")
    local freq = clamp(parameters.frequency, 0, sr / 2)
    -- Resonance / quality factor
    local Q = clamp(parameters.Q or 1, 0, 100)
    -- EQ filter gain
    local gain = clamp(parameters.gain or 0, -60, 60)
    local wet = clamp(parameters.wet or 1, 0, 1)
    local type = parameters.type

    local a0, a1, a2, b0, b1, b2
    local x0, x1, x2 = 0, 0, 0
    local y0, y1, y2 = 0, 0, 0

    local w0 = 2 * pi * freq / sr
    local alpha = sin(w0) / (2 * Q)
    local cos_w0 = cos(w0)
    local A = 10 ^ (gain / 40)

    local function process(x0)
        y2, y1 = y1, y0
        y0 = (b0 / a0) * x0 + (b1 / a0) * x1 + (b2 / a0) * x2 - (a1 / a0) * y1 - (a2 / a0) * y2
        x2, x1 = x1, x0
        return y0
    end

    if type == "lowpass" then
        b0 =  (1 - cos_w0)/2
        b1 =   1 - cos_w0
        b2 =  (1 - cos_w0)/2
        a0 =   1 + alpha
        a1 =  -2*cos_w0
        a2 =   1 - alpha
    elseif type == "highpass" then
        b0 =  (1 + cos_w0)/2
        b1 = -(1 + cos_w0)
        b2 =  (1 + cos_w0)/2
        a0 =   1 + alpha
        a1 =  -2*cos_w0
        a2 =   1 - alpha
    elseif type == "bandpass" then
        b0 =   Q * alpha
        b1 =   0
        b2 =   Q * alpha
        a0 =   1 + alpha
        a1 =  -2*cos_w0
        a2 =   1 - alpha
    elseif type == "notch" then
        b0 =   1
        b1 =  -2*cos_w0
        b2 =   1
        a0 =   1 + alpha
        a1 =  -2*cos_w0
        a2 =   1 - alpha
    elseif type == "allpass" then
        b0 =   1 - alpha
        b1 =  -2*cos_w0
        b2 =   1 + alpha
        a0 =   1 + alpha
        a1 =  -2*cos_w0
        a2 =   1 - alpha
    elseif type == "peakeq" then
        b0 =   1 + alpha*A
        b1 =  -2*cos_w0
        b2 =   1 - alpha*A
        a0 =   1 + alpha/A
        a1 =  -2*cos_w0
        a2 =   1 - alpha/A
    elseif type == "lowshelf" then
        local tsaa = 2 * sqrt(A) * alpha
        b0 =    A*( (A+1) - (A-1)*cos_w0 + tsaa            )
        b1 =  2*A*( (A-1) - (A+1)*cos_w0                   )
        b2 =    A*( (A+1) - (A-1)*cos_w0 - tsaa            )
        a0 =        (A+1) + (A-1)*cos_w0 + tsaa
        a1 =   -2*( (A-1) + (A+1)*cos_w0                   )
        a2 =        (A+1) + (A-1)*cos_w0 - tsaa
    elseif type == "highshelf" then
        local tsaa = 2 * sqrt(A) * alpha
        b0 =    A*( (A+1) + (A-1)*cos_w0 + tsaa            )
        b1 = -2*A*( (A-1) + (A+1)*cos_w0                   )
        b2 =    A*( (A+1) + (A-1)*cos_w0 - tsaa            )
        a0 =        (A+1) - (A-1)*cos_w0 + tsaa
        a1 =    2*( (A-1) - (A+1)*cos_w0                   )
        a2 =        (A+1) - (A-1)*cos_w0 - tsaa
    else
        if type == nil then
            error("Filter type is a nil value")
        else
            error("Unsupported filter type: '"..type.."'")
        end
    end

    local sampleCount = sound:getSampleCount() * ch - 1
    local startSample = 0
    local finishSample = sampleCount

    if parameters.start then
        startSample = parameters.start * sr * ch
    elseif parameters.startSample then
        startSample = parameters.startSample
    end

    if parameters.finish then
        -- subtract one because sound indexes are zero-based
        finishSample = parameters.finish * sr * ch - 1
    elseif parameters.finishSample then
        finishSample = parameters.finishSample
    end

    startSample = math.floor(startSample)
    finishSample = math.floor(finishSample)
    assert(startSample >= 0, "Start time cannot be less than zero")
    assert(finishSample <= sampleCount, "Finish time cannot be longer than the sound")

    for j = 1, ch do
        if state then
            x0, x1, x2 = state.x0, state.x1, state.x2
            y0, y1, y2 = state.y0, state.y1, state.y2
        else
            x0, x1, x2 = 0, 0, 0
            y0, y1, y2 = 0, 0, 0
        end
        for i=startSample + j - 1, finishSample, ch do
            local inputSample = sound:getSample(i)
            local outputSample = process(sound:getSample(i))
            outputSample = inputSample * (1 - wet) + (outputSample * wet)
            sound:setSample(i, clamp(outputSample, -1, 1))
        end
    end

    state = state or {}
    state.x0, state.x1, state.x2 = x0, x1, x2
    state.y0, state.y1, state.y2 = y0, y1, y2

    return sound, state
end

--- @function filter
--- Filters a sound with different filters and settings.
--[=[--

**Example**
```lua
    -- Filter out all sounds below 1000Hz.
    sone.filter(sound, {
        type = "highpass",
        frequency = 1000,
    })
```
--]=]
--- @param SoundData sound
--- @param FilterParameters parameters
--- @return SoundData, state
function sone.filter(sound, parameters, state)
    return biquadFilter(sound, parameters, state)
end

--- @function amplify
--- Amplifies a sound by some amount. Clipping will occur if the gain amount is too high.
--[=[--

**Example**
```lua
    -- Amplify sound by 6dB.
    sone.amplify(sound, 6)

    -- Deamplify sound by -2.5dB.
    sone.amplify(sound, -2.5)
```
--]=]
--- @param SoundData sound
--- @param number gain Amplification amount in decibels.
--- @return SoundData
function sone.amplify(sound, gain)
    return sone.filter(sound, {
        type = "highshelf",
        frequency = 0,
        gain = gain,
    })
end

--- @function pan
--- Pans a sound to either the left or right channel. Only works for stereo sounds.
--[=[--

**Example**
```lua
    -- Play sound 85% in the right channel, 15% in the left channel.
    sone.pan(sound, 0.85)
```
--]=]
--- @param SoundData sound
--- @param number pan How to pan the input (range: -1.0 to 1.0), where -1.0 is far left, 1.0 is far right, and 0.0 is dead center.
--- @return SoundData
function sone.pan(sound, pan)
    assert(sound:getChannels() == 2, "Pan only works for stereo sounds.")

    pan = clamp((1 + pan) * 0.5, 0, 1)

    local leftGain = sqrt(pan)
    local rightGain = sqrt(1 - pan)

    local gains = {
        [0] = rightGain,
        [1] = leftGain,
    }

    local sampleCount = sound:getSampleCount() * sound:getChannels() - 1
    for i=0, sampleCount do
        sound:setSample(i, sound:getSample(i) * gains[i%2])
    end

    return sound
end

--- @function fadeIn
--- Fades in a sound to full volume over a number of seconds.
--[=[--

**Example**
```lua
    -- Fade in sound linearly over 3 seconds.
    sone.fadeIn(sound, 3)

    -- Fade in sound exponentially over 10 seconds.
    sone.fadeIn(sound, 10, "inOutExpo")
```
--]=]
--- @param SoundData sound
--- @param number seconds How long the fade will take.
--- @param FadeType fadeType (optional) Which fade curve to use. Default is linear.
--- @return SoundData
function sone.fadeIn(sound, seconds, fadeType)
    fadeType = fadeType or "linear"
    local ease = easing[fadeType]

    local sampleCount = sound:getSampleCount() * sound:getChannels() - 1
    local start = 0
    local finish = seconds * sound:getSampleRate() * sound:getChannels()
    local t

    assert(finish <= sampleCount, "Fade in cannot be longer than the sound")

    for i=start, finish do
        t = ease(i, start, 1, finish)
        sound:setSample(i, t * sound:getSample(i))
    end

    return sound
end

--- @function fadeOut
--- Fades out a sound to zero volume over a number of seconds.
--[=[--

**Example**
```lua
    -- Fade out sound linearly over 3 seconds.
    sone.fadeOut(sound, 3)

    -- Fade out sound exponentially over 10 seconds.
    sone.fadeOut(sound, 10, "inOutExpo")
```
--]=]
--- @param SoundData sound
--- @param number seconds How long the fade will take.
--- @param FadeType fadeType (optional) Which fade curve to use. Default is linear.
--- @return SoundData
function sone.fadeOut(sound, seconds, fadeType)
    fadeType = fadeType or "linear"
    local ease = easing[fadeType]

    local sampleCount = sound:getSampleCount() * sound:getChannels() - 1
    local duration = seconds * sound:getSampleRate() * sound:getChannels()
    local finish = sound:getSampleCount() * sound:getChannels() - 1
    local start = finish - duration
    local t

    assert(start >= 0, "Fade out cannot be longer than the sound")

    for i=start, finish do
        t = 1 - ease(i - start, 0, 1, finish - start)
        sound:setSample(i, t * sound:getSample(i))
    end

    return sound
end

--- @function fadeInOut
--- Fades a sound at the beginning and at the end. The first N seconds will be faded in, and the last N seconds will be faded out.
--[=[--

**Example**
```lua
    -- Fade the first 5 seconds and last 5 seconds of a sound.
    sone.fadeInOut(sound, 5)
```
--]=]
--- @param SoundData sound
--- @param number seconds How long the fade will take.
--- @param FadeType fadeType (optional) Which fade curve to use. Default is linear.
--- @return SoundData
function sone.fadeInOut(sound, seconds, fadeType)
    sone.fadeIn(sound, seconds, fadeType)
    return sone.fadeOut(sound, seconds, fadeType)
end

--- @function copy
--- Makes a copy of a SoundData.
--[=[--

**Example**
```lua
    copy = sone.copy(sound)
```
--]=]
--- @param SoundData sound The sound to copy.
--- @param boolean copyOverData (optional) If false, only a new SoundData will be created with the same sample count, sample rate, bit depth, and channels. The actual signal data will not be copied.
--- @return SoundData The copied sound.
function sone.copy(sound, copyOverData)
    local copy = love.sound.newSoundData(sound:getSampleCount(), sound:getSampleRate(), sound:getBitDepth(), sound:getChannels())
    copyOverData = copyOverData == nil and true or copyOverData

    if copyOverData then
        local sampleCount = sound:getSampleCount() * sound:getChannels() - 1
        for i=0, sampleCount do
            copy:setSample(i, sound:getSample(i))
        end
    end

    return copy
end

--- @env Using sone for sound processing
--- Examples of using sone to process a sound.
--[=[--
```lua
    sone = require 'sone'
    sound = love.sound.newSoundData(...)

    -- NOTE: All sone functions will alter the sound data directly.

    -- Filter out all sounds above 150Hz.
    sone.filter(sound, {
        type = "lowpass",
        frequency = 150,
    })

    -- Boost sound at 1000Hz
    sone.filter(sound, {
        type = "peakeq",
        frequency = 1000,
        gain = 9,
    })

    -- Boost everything below 150Hz by 6dB
    sone.filter(sound, {
        type = "lowshelf",
        frequency = 150,
        gain = 6,
    })

    -- Amplify sound by 3dB
    sone.amplify(sound, 3)

    -- Pan sound to the left ear
    sone.pan(sound, -1)

    -- Fade in sound over 5 seconds
    sone.fadeIn(sound, 5)

    -- Fade in sound over 5 seconds, and also fade out the last 5 seconds
    sone.fadeInOut(sound, 5)

    -- Play the sound data
    love.audio.newSource(sound):play()
```
--]=]

--- @type FilterType
--- Filters that are able to be used with the filter function. (`sone.filter`)
-- TODO: descriptions for these
--- @field string lowpass
--- @field string highpass
--- @field string bandpass
--- @field string notch
--- @field string allpass
--- @field string peakeq
--- @field string lowshelf
--- @field string highshelf
--- @end type

--- @type FadeType
--- @field string linear
--- @field string inQuad
--- @field string outQuad
--- @field string inOutQuad
--- @field string outInQuad
--- @field string inCubic
--- @field string outCubic
--- @field string inOutCubic
--- @field string outInCubic
--- @field string inQuart
--- @field string outQuart
--- @field string inOutQuart
--- @field string outInQuart
--- @field string inQuint
--- @field string outQuint
--- @field string inOutQuint
--- @field string outInQuint
--- @field string inSine
--- @field string outSine
--- @field string inOutSine
--- @field string outInSine
--- @field string inExpo
--- @field string outExpo
--- @field string inOutExpo
--- @field string outInExpo
--- @field string inCirc
--- @field string outCirc
--- @field string inOutCirc
--- @field string outInCirc

--- @type FilterParameters
--- A table of the possible parameters for the filter function.
--- @field FilterType type **REQUIRED** The type of filter to use.

--- @field number frequency **REQUIRED** The center/target frequency (in Hz).
--- Ranges from 0Hz to (Sampling rate) / 2 Hz.

--- @field number Q (optional) The quality factor to use.
--- Ranges from 0 to 100. Default: 1.

--- @field number gain (optional) The gain (in dB) to use for EQ filters.
--- Ranges from -60dB to 60dB. Default: 0dB.

--- @field number start (optional) The time (in seconds) for the start of the filtered section.
--- Default: 0 seconds.

--- @field number finish (optional) The time (in seconds) for the finish of the filtered section.
--- Default: the duration of the sound.

--- @field number startSample (optional) The start (in samples) of the filtered section.
--- Default: 0.

--- @field number finishSample (optional) The finish (in samples) of the filtered section.
--- Default: the number of samples in the sound.

--- @field number wet (optional) The wetness of the filtered sound, or the percentage of the effect that will be applied.
--- Default: 1 (100%). Ranges from 0 (0%) to 1 (100%).

--- @type SoundData
--- A SoundData object from LOVE.
--- https://www.love2d.org/wiki/SoundData
--- @end type

return sone
