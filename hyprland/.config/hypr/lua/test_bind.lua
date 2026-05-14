-- Test different bind syntaxes

-- Revert lines 5-6 to single-string format
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("/usr/bin/ghostty"))
hl.bind("SUPER + B", hl.dsp.exec_cmd("/usr/bin/brave"))

-- Test different combinations for line 7
hl.bind("SUPER + CTRL", "E", hl.dsp.exec_cmd("/usr/bin/smile"))
hl.bind("SUPER", "CTRL + E", hl.dsp.exec_cmd("/usr/bin/speedcrunch"))
hl.bind("SUPER + CTRL + E", hl.dsp.exec_cmd("/usr/bin/smile"))
