# sccache — rustc compile cache. See zsh/.config/zshrc/19-sccache for why
# SCCACHE_DIR is pinned to an absolute path. No-op without sccache.
if command -q sccache
    set -gx RUSTC_WRAPPER sccache
    set -gx SCCACHE_DIR $HOME/.cache/sccache
    set -gx SCCACHE_CACHE_SIZE 20G
end
