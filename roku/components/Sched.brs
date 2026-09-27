' Channels on ONE clock (ROKU-DESIGN 6.7, ORPHANED-FILMS #2). The schedule is
' no longer computed here: the pipeline publishes one UTC timeline per channel
' (channel-schedule.json, tools/build_channel_schedule.py) and every platform
' plays from it, so a viewer on any device finds the same programme on the
' same channel at the same minute. This file only lays the published days out
' as slots and prints them in the viewer's own time.
'
' Every second here is UTC epoch seconds (roDateTime.AsSeconds() without
' ToLocalTime). They fit a 32-bit Integer until 2038. Local time is applied
' ONLY when a clock is printed.

function nowUtcSeconds() as Integer
    return CreateObject("roDateTime").AsSeconds()
end function

' Seconds to add to a UTC instant to read it on the viewer's wall clock.
function utcOffsetSeconds() as Integer
    utc = CreateObject("roDateTime")
    loc = CreateObject("roDateTime")
    loc.FromSeconds(utc.AsSeconds())
    loc.ToLocalTime()
    return loc.AsSeconds() - utc.AsSeconds()
end function

' [{prog: [id, title, runtime, url, type], startS, endS}] for one channel of
' the published file, from the first programme still on the air onward. A
' day's first slot starts at its `start`; each next one where the previous
' ended plus the file's `gap`.
function slotsFromSchedule(ch as Object, programs as Object, gap as Integer, nowS as Integer) as Object
    slots = []
    if ch = invalid or ch.days = invalid or programs = invalid then return slots
    keys = []
    for each k in ch.days
        keys.Push(k)
    end for
    keys.Sort()
    for each k in keys
        d = ch.days[k]
        if d <> invalid and d.slots <> invalid and d.start <> invalid
            t = Int(d.start)
            for each s in d.slots
                secs = Int(s[1])
                endS = t + secs
                if endS > nowS
                    p = programs[fmt(s[0])]
                    if p <> invalid
                        slots.Push({ prog: [fmt(s[0]), p[0], p[1], p[2], p[3]], startS: t, endS: endS })
                    end if
                end if
                t = endS + gap
            end for
        end if
    end for
    return slots
end function

' A UTC instant printed on the viewer's clock, "h:mm AM".
function clockLabel(utcSeconds as Integer) as String
    s = (utcSeconds + utcOffsetSeconds()) mod 86400
    if s < 0 then s = s + 86400
    h = Int(s / 3600)
    mi = Int((s - h * 3600) / 60)
    ap = "AM"
    if h >= 12 then ap = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    mm = fmt(mi)
    if mi < 10 then mm = "0" + mm
    return fmt(h12) + ":" + mm + " " + ap
end function
