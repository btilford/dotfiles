# tde — terminal development environment. Shell hooks report each command's start,
# end and exit code to tde, and wrap `tde` so `tde cd <feature>` is a real cd.
#
# Sourced rather than committed: tde never writes rc files, and the generated
# snippet follows whatever version of tde is installed on this host.

if command -q tde
    tde shell init fish | source
end
