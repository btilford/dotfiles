# GENERATED FILE — do not hand-edit.
#   grype completion bash > bash/.bash_completions/grype.bash
# Regenerate after a grype upgrade. Sourced by bash/.config/bashrc/20-grype.

# bash completion for grype                                -*- shell-script -*-

__grype_debug() {
  if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
    echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
  fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__grype_init_completion() {
  COMPREPLY=()
  _get_comp_words_by_ref "$@" cur prev words cword
}

__grype_index_of_word() {
  local w word=$1
  shift
  index=0
  for w in "$@"; do
    [[ $w = "$word" ]] && return
    index=$((index + 1))
  done
  index=-1
}

__grype_contains_word() {
  local w word=$1
  shift
  for w in "$@"; do
    [[ $w = "$word" ]] && return
  done
  return 1
}

__grype_handle_go_custom_completion() {
  __grype_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

  local shellCompDirectiveError=1
  local shellCompDirectiveNoSpace=2
  local shellCompDirectiveNoFileComp=4
  local shellCompDirectiveFilterFileExt=8
  local shellCompDirectiveFilterDirs=16

  local out requestComp lastParam lastChar comp directive args

  # Prepare the command to request completions for the program.
  # Calling ${words[0]} instead of directly grype allows handling aliases
  args=("${words[@]:1}")
  # Disable ActiveHelp which is not supported for bash completion v1
  requestComp="GRYPE_ACTIVE_HELP=0 ${words[0]} __completeNoDesc ${args[*]}"

  lastParam=${words[$((${#words[@]} - 1))]}
  lastChar=${lastParam:$((${#lastParam} - 1)):1}
  __grype_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

  if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
    # If the last parameter is complete (there is a space following it)
    # We add an extra empty parameter so we can indicate this to the go method.
    __grype_debug "${FUNCNAME[0]}: Adding extra empty parameter"
    requestComp="${requestComp} \"\""
  fi

  __grype_debug "${FUNCNAME[0]}: calling ${requestComp}"
  # Use eval to handle any environment variables and such
  out=$(eval "${requestComp}" 2> /dev/null)

  # Extract the directive integer at the very end of the output following a colon (:)
  directive=${out##*:}
  # Remove the directive
  out=${out%:*}
  if [ "${directive}" = "${out}" ]; then
    # There is not directive specified
    directive=0
  fi
  __grype_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
  __grype_debug "${FUNCNAME[0]}: the completions are: ${out}"

  if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
    # Error code.  No completion.
    __grype_debug "${FUNCNAME[0]}: received error from custom completion go code"
    return
  else
    if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
      if [[ $(type -t compopt) = "builtin" ]]; then
        __grype_debug "${FUNCNAME[0]}: activating no space"
        compopt -o nospace
      fi
    fi
    if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
      if [[ $(type -t compopt) = "builtin" ]]; then
        __grype_debug "${FUNCNAME[0]}: activating no file completion"
        compopt +o default
      fi
    fi
  fi

  if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
    # File extension filtering
    local fullFilter filter filteringCmd
    # Do not use quotes around the $out variable or else newline
    # characters will be kept.
    for filter in ${out}; do
      fullFilter+="$filter|"
    done

    filteringCmd="_filedir $fullFilter"
    __grype_debug "File filtering command: $filteringCmd"
    $filteringCmd
  elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
    # File completion for directories only
    local subdir
    # Use printf to strip any trailing newline
    subdir=$(printf "%s" "${out}")
    if [ -n "$subdir" ]; then
      __grype_debug "Listing directories in $subdir"
      __grype_handle_subdirs_in_dir_flag "$subdir"
    else
      __grype_debug "Listing directories in ."
      _filedir -d
    fi
  else
    while IFS='' read -r comp; do
      COMPREPLY+=("$comp")
    done < <(compgen -W "${out}" -- "$cur")
  fi
}

__grype_handle_reply() {
  __grype_debug "${FUNCNAME[0]}"
  local comp
  case $cur in
    -*)
      if [[ $(type -t compopt) = "builtin" ]]; then
        compopt -o nospace
      fi
      local allflags
      if [ ${#must_have_one_flag[@]} -ne 0 ]; then
        allflags=("${must_have_one_flag[@]}")
      else
        allflags=("${flags[*]} ${two_word_flags[*]}")
      fi
      while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
      done < <(compgen -W "${allflags[*]}" -- "$cur")
      if [[ $(type -t compopt) = "builtin" ]]; then
        [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
      fi

      # complete after --flag=abc
      if [[ $cur == *=* ]]; then
        if [[ $(type -t compopt) = "builtin" ]]; then
          compopt +o nospace
        fi

        local index flag
        flag="${cur%=*}"
        __grype_index_of_word "${flag}" "${flags_with_completion[@]}"
        COMPREPLY=()
        if [[ ${index} -ge 0 ]]; then
          PREFIX=""
          cur="${cur#*=}"
          ${flags_completion[${index}]}
          if [ -n "${ZSH_VERSION:-}" ]; then
            # zsh completion needs --flag= prefix
            eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
          fi
        fi
      fi

      if [[ -z "${flag_parsing_disabled}" ]]; then
        # If flag parsing is enabled, we have completed the flags and can return.
        # If flag parsing is disabled, we may not know all (or any) of the flags, so we fallthrough
        # to possibly call handle_go_custom_completion.
        return 0
      fi
      ;;
  esac

  # check if we are handling a flag with special work handling
  local index
  __grype_index_of_word "${prev}" "${flags_with_completion[@]}"
  if [[ ${index} -ge 0 ]]; then
    ${flags_completion[${index}]}
    return
  fi

  # we are parsing a flag and don't have a special handler, no completion
  if [[ ${cur} != "${words[cword]}" ]]; then
    return
  fi

  local completions
  completions=("${commands[@]}")
  if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
    completions+=("${must_have_one_noun[@]}")
  elif [[ -n "${has_completion_function}" ]]; then
    # if a go completion function is provided, defer to that function
    __grype_handle_go_custom_completion
  fi
  if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
    completions+=("${must_have_one_flag[@]}")
  fi
  while IFS='' read -r comp; do
    COMPREPLY+=("$comp")
  done < <(compgen -W "${completions[*]}" -- "$cur")

  if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
    while IFS='' read -r comp; do
      COMPREPLY+=("$comp")
    done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
  fi

  if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
    if declare -F __grype_custom_func > /dev/null; then
      # try command name qualified custom func
      __grype_custom_func
    else
      # otherwise fall back to unqualified for compatibility
      declare -F __custom_func > /dev/null && __custom_func
    fi
  fi

  # available in bash-completion >= 2, not always present on macOS
  if declare -F __ltrim_colon_completions > /dev/null; then
    __ltrim_colon_completions "$cur"
  fi

  # If there is only 1 completion and it is a flag with an = it will be completed
  # but we don't want a space after the =
  if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
    compopt -o nospace
  fi
}

# The arguments should be in the form "ext1|ext2|extn"
__grype_handle_filename_extension_flag() {
  local ext="$1"
  _filedir "@(${ext})"
}

__grype_handle_subdirs_in_dir_flag() {
  local dir="$1"
  pushd "${dir}" > /dev/null 2>&1 && _filedir -d && popd > /dev/null 2>&1 || return
}

__grype_handle_flag() {
  __grype_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

  # if a command required a flag, and we found it, unset must_have_one_flag()
  local flagname=${words[c]}
  local flagvalue=""
  # if the word contained an =
  if [[ ${words[c]} == *"="* ]]; then
    flagvalue=${flagname#*=} # take in as flagvalue after the =
    flagname=${flagname%=*}  # strip everything after the =
    flagname="${flagname}="  # but put the = back
  fi
  __grype_debug "${FUNCNAME[0]}: looking for ${flagname}"
  if __grype_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
    must_have_one_flag=()
  fi

  # if you set a flag which only applies to this command, don't show subcommands
  if __grype_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
    commands=()
  fi

  # keep flag value with flagname as flaghash
  # flaghash variable is an associative array which is only supported in bash > 3.
  if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
    if [ -n "${flagvalue}" ]; then
      flaghash[${flagname}]=${flagvalue}
    elif [ -n "${words[$((c + 1))]}" ]; then
      flaghash[${flagname}]=${words[$((c + 1))]}
    else
      flaghash[${flagname}]="true" # pad "true" for bool flag
    fi
  fi

  # skip the argument to a two word flag
  if [[ ${words[c]} != *"="* ]] && __grype_contains_word "${words[c]}" "${two_word_flags[@]}"; then
    __grype_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
    c=$((c + 1))
    # if we are looking for a flags value, don't show commands
    if [[ $c -eq $cword ]]; then
      commands=()
    fi
  fi

  c=$((c + 1))

}

__grype_handle_noun() {
  __grype_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

  if __grype_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
    must_have_one_noun=()
  elif __grype_contains_word "${words[c]}" "${noun_aliases[@]}"; then
    must_have_one_noun=()
  fi

  nouns+=("${words[c]}")
  c=$((c + 1))
}

__grype_handle_command() {
  __grype_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

  local next_command
  if [[ -n ${last_command} ]]; then
    next_command="_${last_command}_${words[c]//:/__}"
  else
    if [[ $c -eq 0 ]]; then
      next_command="_grype_root_command"
    else
      next_command="_${words[c]//:/__}"
    fi
  fi
  c=$((c + 1))
  __grype_debug "${FUNCNAME[0]}: looking for ${next_command}"
  declare -F "$next_command" > /dev/null && $next_command
}

__grype_handle_word() {
  if [[ $c -ge $cword ]]; then
    __grype_handle_reply
    return
  fi
  __grype_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
  if [[ "${words[c]}" == -* ]]; then
    __grype_handle_flag
  elif __grype_contains_word "${words[c]}" "${commands[@]}"; then
    __grype_handle_command
  elif [[ $c -eq 0 ]]; then
    __grype_handle_command
  elif __grype_contains_word "${words[c]}" "${command_aliases[@]}"; then
    # aliashash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
      words[c]=${aliashash[${words[c]}]}
      __grype_handle_command
    else
      __grype_handle_noun
    fi
  else
    __grype_handle_noun
  fi
  __grype_handle_word
}

_grype_completion() {
  last_command="grype_completion"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--help")
  flags+=("-h")
  local_nonpersistent_flags+=("--help")
  local_nonpersistent_flags+=("-h")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  must_have_one_noun+=("bash")
  must_have_one_noun+=("fish")
  must_have_one_noun+=("zsh")
  noun_aliases=()
}

_grype_config_locations() {
  last_command="grype_config_locations"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--all")
  local_nonpersistent_flags+=("--all")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_config() {
  last_command="grype_config"

  command_aliases=()

  commands=()
  commands+=("locations")

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--load")
  local_nonpersistent_flags+=("--load")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_check() {
  last_command="grype_db_check"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_delete() {
  last_command="grype_db_delete"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_diff() {
  last_command="grype_db_diff"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--packages")
  local_nonpersistent_flags+=("--packages")
  flags+=("--vulns")
  local_nonpersistent_flags+=("--vulns")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_import() {
  last_command="grype_db_import"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_list() {
  last_command="grype_db_list"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_providers() {
  last_command="grype_db_providers"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_search_vuln() {
  last_command="grype_db_search_vuln"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--fixed-state=")
  two_word_flags+=("--fixed-state")
  local_nonpersistent_flags+=("--fixed-state")
  local_nonpersistent_flags+=("--fixed-state=")
  flags+=("--limit=")
  two_word_flags+=("--limit")
  local_nonpersistent_flags+=("--limit")
  local_nonpersistent_flags+=("--limit=")
  flags+=("--modified-after=")
  two_word_flags+=("--modified-after")
  local_nonpersistent_flags+=("--modified-after")
  local_nonpersistent_flags+=("--modified-after=")
  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--provider=")
  two_word_flags+=("--provider")
  local_nonpersistent_flags+=("--provider")
  local_nonpersistent_flags+=("--provider=")
  flags+=("--published-after=")
  two_word_flags+=("--published-after")
  local_nonpersistent_flags+=("--published-after")
  local_nonpersistent_flags+=("--published-after=")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_search() {
  last_command="grype_db_search"

  command_aliases=()

  commands=()
  commands+=("vuln")
  if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
    command_aliases+=("vulnerabilities")
    aliashash["vulnerabilities"]="vuln"
    command_aliases+=("vulnerability")
    aliashash["vulnerability"]="vuln"
    command_aliases+=("vulns")
    aliashash["vulns"]="vuln"
  fi

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--broad-cpe-matching")
  local_nonpersistent_flags+=("--broad-cpe-matching")
  flags+=("--distro=")
  two_word_flags+=("--distro")
  local_nonpersistent_flags+=("--distro")
  local_nonpersistent_flags+=("--distro=")
  flags+=("--ecosystem=")
  two_word_flags+=("--ecosystem")
  local_nonpersistent_flags+=("--ecosystem")
  local_nonpersistent_flags+=("--ecosystem=")
  flags+=("--fixed-state=")
  two_word_flags+=("--fixed-state")
  local_nonpersistent_flags+=("--fixed-state")
  local_nonpersistent_flags+=("--fixed-state=")
  flags+=("--limit=")
  two_word_flags+=("--limit")
  local_nonpersistent_flags+=("--limit")
  local_nonpersistent_flags+=("--limit=")
  flags+=("--modified-after=")
  two_word_flags+=("--modified-after")
  local_nonpersistent_flags+=("--modified-after")
  local_nonpersistent_flags+=("--modified-after=")
  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--pkg=")
  two_word_flags+=("--pkg")
  local_nonpersistent_flags+=("--pkg")
  local_nonpersistent_flags+=("--pkg=")
  flags+=("--provider=")
  two_word_flags+=("--provider")
  local_nonpersistent_flags+=("--provider")
  local_nonpersistent_flags+=("--provider=")
  flags+=("--published-after=")
  two_word_flags+=("--published-after")
  local_nonpersistent_flags+=("--published-after")
  local_nonpersistent_flags+=("--published-after=")
  flags+=("--vuln=")
  two_word_flags+=("--vuln")
  local_nonpersistent_flags+=("--vuln")
  local_nonpersistent_flags+=("--vuln=")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_status() {
  last_command="grype_db_status"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db_update() {
  last_command="grype_db_update"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_db() {
  last_command="grype_db"

  command_aliases=()

  commands=()
  commands+=("check")
  commands+=("delete")
  commands+=("diff")
  commands+=("import")
  commands+=("list")
  commands+=("providers")
  commands+=("search")
  commands+=("status")
  commands+=("update")

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_explain() {
  last_command="grype_explain"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--id=")
  two_word_flags+=("--id")
  local_nonpersistent_flags+=("--id")
  local_nonpersistent_flags+=("--id=")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_help() {
  last_command="grype_help"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  has_completion_function=1
  noun_aliases=()
}

_grype_version() {
  last_command="grype_version"

  command_aliases=()

  commands=()

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--verbose")
  flags+=("-v")

  must_have_one_flag=()
  must_have_one_noun=()
  noun_aliases=()
}

_grype_root_command() {
  last_command="grype"

  command_aliases=()

  commands=()
  commands+=("completion")
  commands+=("config")
  commands+=("db")
  commands+=("explain")
  commands+=("help")
  commands+=("version")

  flags=()
  two_word_flags=()
  local_nonpersistent_flags=()
  flags_with_completion=()
  flags_completion=()

  flags+=("--add-cpes-if-none")
  local_nonpersistent_flags+=("--add-cpes-if-none")
  flags+=("--by-cve")
  local_nonpersistent_flags+=("--by-cve")
  flags+=("--config=")
  two_word_flags+=("--config")
  two_word_flags+=("-c")
  flags+=("--distro=")
  two_word_flags+=("--distro")
  local_nonpersistent_flags+=("--distro")
  local_nonpersistent_flags+=("--distro=")
  flags+=("--exclude=")
  two_word_flags+=("--exclude")
  local_nonpersistent_flags+=("--exclude")
  local_nonpersistent_flags+=("--exclude=")
  flags+=("--fail-on=")
  two_word_flags+=("--fail-on")
  two_word_flags+=("-f")
  local_nonpersistent_flags+=("--fail-on")
  local_nonpersistent_flags+=("--fail-on=")
  local_nonpersistent_flags+=("-f")
  flags+=("--file=")
  two_word_flags+=("--file")
  local_nonpersistent_flags+=("--file")
  local_nonpersistent_flags+=("--file=")
  flags+=("--from=")
  two_word_flags+=("--from")
  local_nonpersistent_flags+=("--from")
  local_nonpersistent_flags+=("--from=")
  flags+=("--ignore-states=")
  two_word_flags+=("--ignore-states")
  local_nonpersistent_flags+=("--ignore-states")
  local_nonpersistent_flags+=("--ignore-states=")
  flags+=("--name=")
  two_word_flags+=("--name")
  local_nonpersistent_flags+=("--name")
  local_nonpersistent_flags+=("--name=")
  flags+=("--only-fixed")
  local_nonpersistent_flags+=("--only-fixed")
  flags+=("--only-notfixed")
  local_nonpersistent_flags+=("--only-notfixed")
  flags+=("--output=")
  two_word_flags+=("--output")
  two_word_flags+=("-o")
  local_nonpersistent_flags+=("--output")
  local_nonpersistent_flags+=("--output=")
  local_nonpersistent_flags+=("-o")
  flags+=("--platform=")
  two_word_flags+=("--platform")
  local_nonpersistent_flags+=("--platform")
  local_nonpersistent_flags+=("--platform=")
  flags+=("--profile=")
  two_word_flags+=("--profile")
  flags+=("--quiet")
  flags+=("-q")
  flags+=("--scope=")
  two_word_flags+=("--scope")
  two_word_flags+=("-s")
  local_nonpersistent_flags+=("--scope")
  local_nonpersistent_flags+=("--scope=")
  local_nonpersistent_flags+=("-s")
  flags+=("--show-suppressed")
  local_nonpersistent_flags+=("--show-suppressed")
  flags+=("--sort-by=")
  two_word_flags+=("--sort-by")
  local_nonpersistent_flags+=("--sort-by")
  local_nonpersistent_flags+=("--sort-by=")
  flags+=("--template=")
  two_word_flags+=("--template")
  two_word_flags+=("-t")
  local_nonpersistent_flags+=("--template")
  local_nonpersistent_flags+=("--template=")
  local_nonpersistent_flags+=("-t")
  flags+=("--verbose")
  flags+=("-v")
  flags+=("--vex=")
  two_word_flags+=("--vex")
  local_nonpersistent_flags+=("--vex")
  local_nonpersistent_flags+=("--vex=")

  must_have_one_flag=()
  must_have_one_noun=()
  has_completion_function=1
  noun_aliases=()
}

__start_grype() {
  local cur prev words cword split
  declare -A flaghash 2> /dev/null || :
  declare -A aliashash 2> /dev/null || :
  if declare -F _init_completion > /dev/null 2>&1; then
    _init_completion -s || return
  else
    __grype_init_completion -n "=" || return
  fi

  local c=0
  local flag_parsing_disabled=
  local flags=()
  local two_word_flags=()
  local local_nonpersistent_flags=()
  local flags_with_completion=()
  local flags_completion=()
  local commands=("grype")
  local command_aliases=()
  local must_have_one_flag=()
  local must_have_one_noun=()
  local has_completion_function=""
  local last_command=""
  local nouns=()
  local noun_aliases=()

  __grype_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
  complete -o default -F __start_grype grype
else
  complete -o default -o nospace -F __start_grype grype
fi

# ex: ts=4 sw=4 et filetype=sh
