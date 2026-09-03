#    _               _              
#   | |__   __ _ ___| |__  _ __ ___ 
#   | '_ \ / _` / __| '_ \| '__/ __|
#  _| |_) | (_| \__ \ | | | | | (__ 
# (_)_.__/ \__,_|___/_| |_|_|  \___|
# 
# -----------------------------------------------------
# ML4W bashrc loader
# -----------------------------------------------------

# DON'T CHANGE THIS FILE

# You can define your custom configuration by adding
# files in ~/.config/bashrc 
# or by creating a folder ~/.config/bashrc/custom
# with copies of files from ~/.config/bashrc 
# You can also create a .bashrc_custom file in your home directory
# -----------------------------------------------------

# -----------------------------------------------------
# Load modular configarion
# -----------------------------------------------------

for f in ~/.config/bashrc/*; do 
    if [ ! -d $f ] ;then
        c=`echo $f | sed -e "s=.config/bashrc=.config/bashrc/custom="`
        [[ -f $c ]] && source $c || source $f
    fi
done

# -----------------------------------------------------
# Load local-only overrides (if exists)
# -----------------------------------------------------

if [ -f ~/.bashrc_local ] ;then
    source ~/.bashrc_local
fi


# $VOL_SCREENSHOT_ARCHIVE / $DOTFILES_SCREENSHOT_ARCHIVE are machine-local (they
# point into a notes vault that only exists on some hosts) — set them in
# ~/.bashrc_local, sourced above. See scripts/visuals/README.md.

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

[[ -f "${HOME}/.bash_completions/hf.sh" ]] && source "${HOME}/.bash_completions/hf.sh"

# worktrunk must stay in this file, not a ~/.config/bashrc drop-in: `wt config shell
# install` reads only ~/.bashrc, so it appends this line again whenever it is absent.
if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init bash)"; fi
