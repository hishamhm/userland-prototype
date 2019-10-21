local denver = {
    _VERSION         = 'denver v1.0.2',
    _DESCRIPTION    = 'An audio generation module for LÖVE2D',
    _URL            = 'http://github.com/superzazu/denver.lua',
    _LICENSE        = [[
Copyright (c) 2015 Nicolas Allemand

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
]]
}

denver.rate = 44100
denver.bits = 16
denver.channel = 1
denver.base_freq = 440 -- A4 = 440

local oscillators = {}

-- returns a LOVE2D audio source with a waveform
-- examples :
--    s = denver.get({waveform='sinus', frequency=440, length=1})
--    s = denver.get{waveform='square', frequency='E#3'}
--
-- note: creates one period-sample by default; that allows user to loop the
--       sample (and to have a minimum of RAM used)
denver.get = function (args, ...)
    local waveform = args.waveform or 'sinus'
    local frequency = denver.noteToFrequency(args.frequency)
                      or args.frequency or 440
    local length = args.length or 1 / frequency

    -- creating an empty sample
    local sound_data = love.sound.newSoundData(length * denver.rate,
                                              denver.rate,
                                              denver.bits,
                                              denver.channel)

    -- setting up the oscillator
    if not oscillators[waveform] then
        error('waveform "'.. waveform ..'"" is not supported.', 2)
    end
    local osc = oscillators[waveform](frequency, ...)

    -- filling the sample with values
    local amplitude = 0.2
    for i = 0, length * denver.rate - 1 do
        local sample = osc(freq, denver.rate) * amplitude
        sound_data:setSample(i, sample)
    end

    return sound_data
end

-- you can add your own waves
denver.set = function (wave_type, osc)
    oscillators[wave_type] = osc
end

-- takes a note in parameter and returns a frequency
denver.noteToFrequency = function (note_str)
    if not note_str or type(note_str) ~= 'string' then
        return
    end
    local note_semitones = {C=-9, D=-7, E=-5, F=-4, G=-2, A=0, B=2}

    local semitones = note_semitones[note_str:sub(1, 1)]
    if not semitones then
       return
    end
    local octave = 4
    local alteration = 0

    if note_str:len() == 2 then
        octave = note_str:sub(2, 2)
    elseif note_str:len() == 3 then -- # or flat
        if note_str:sub(2, 2) == '#' then
            semitones = semitones + 1
        elseif note_str:sub(2, 2) == 'b' then
            semitones = semitones - 1
        end
        octave = note_str:sub(3, 3)
    end

    semitones = semitones + 12 * (octave - 4)

    return denver.base_freq * math.pow(math.pow(2, 1 / 12), semitones)
    -- frequency = root * (2^(1/12))^steps (steps(=semitones) can be negative)
end

-- OSCILLATORS
oscillators.sinus = function (f)
    local phase = 0
    return function()
        phase = phase + 2 * math.pi / denver.rate
        if phase >= 2 * math.pi then
            phase = phase - 2 * math.pi
        end
        return math.sin(f * phase)
    end
end

-- thanks https://github.com/zevv/worp/blob/master/lib/Dsp/Saw.lua
oscillators.sawtooth = function (f)
    local dv = 2 * f / denver.rate
    local v = 0
    return function()
        v = v + dv
        if v > 1 then v = v - 2 end
        return v
    end
end

oscillators.square = function (f, pwm)
    pwm = pwm or 0
    if pwm >= 1 or pwm < 0 then
        error('PWM must be between 0 and 1 (0 <= PWM < 1)', 2)
    end
    local saw = oscillators.sawtooth(f)
    return function()
        return saw() < pwm and -1 or 1
    end
end

oscillators.triangle = function (f)
    local dv = 1 / denver.rate
    local v = 0
    local a = 1 -- up or down
    return function()
        v = v + a * dv * 4 * f
        if v > 1 or v < -1 then
            a = a * -1
            v = math.floor(v+.5)
        end
        return v
    end
end

oscillators.whitenoise = function ()
    return function()
        return math.random() * 2 - 1
    end
end

oscillators.pinknoise = function () -- http://www.musicdsp.org/files/pink.txt
    local b0, b1, b2, b3, b4, b5, b6 = 0, 0, 0, 0, 0, 0, 0
    return function()
        local white = math.random() * 2 - 1
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        b3 = 0.86650 * b3 + white * 0.3104856;
        b4 = 0.55000 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.0168980;
        local pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362;
        b6 = white * 0.115926;
        return pink * 0.11 -- (roughly) compensate for gain
    end
end

-- thanks http://noisehack.com/generate-noise-web-audio-api/
oscillators.brownnoise = function ()
    local lastOut = 0
    return function()
        local white = math.random() * 2 - 1
        local out = (lastOut + (0.02 * white)) / 1.02
        lastOut = out
        return out * 3.5 -- (roughly) compensate for gain
    end
end

function denver.is_valid(osc_name)
   return oscillators[osc_name] ~= nil
end


-- Denver, the last dinosaur
-- He's my friend and a whole lot more
-- Denver, the last dinosaur
-- Shows me a world I never saw before

-- Everywhere we go we don't really care
-- If people stop and stare at our pal dino.
-- Creating history thru the rock n' roll spotlight
-- We've got a friend who helps us, we can do alright

-- That's Denver, the last dinosaur
-- He's my friend and a whole lot more
-- Denver, the last dinosaur
-- Shows me a world I never saw before.

return denver
