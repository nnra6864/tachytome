#!/bin/sh
set -eu

repo="nnra6864/tachytome"
url="https://github.com/$repo"

say() {
    printf "%s\n" "$*"
}

warn() {
    printf "Warning: %s\n" "$*" >&2
}

die() {
    printf "Error: %s\n" "$*" >&2
    exit 1
}

has() {
    command -v "$1" >/dev/null 2>&1
}

ask() {
    default="$2"
    hint="[Y/n]"
    [ "$default" = "n" ] && hint="[y/N]"
    if ! ( : </dev/tty ) 2>/dev/null; then
        say "$1 $hint n (no terminal)"
        return 1
    fi
    printf "%s %s " "$1" "$hint" >/dev/tty
    read -r answer </dev/tty || answer=""
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
        [yY]*) return 0 ;;
        *)     return 1 ;;
    esac
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif has sudo; then
        sudo "$@"
    elif has doas; then
        doas "$@"
    else
        warn "Neither sudo nor doas found"
        return 1
    fi
}

pkg_install() {
    if [ "$platform" = "macos" ]; then
        if ! has brew; then
            warn "Homebrew not found, get it from https://brew.sh"
            return 1
        fi
        brew install "$@"
    elif has pacman; then
        as_root pacman -S --needed --noconfirm "$@"
    elif has apt-get; then
        as_root apt-get install -y "$@"
    elif has dnf; then
        as_root dnf install -y "$@"
    elif has zypper; then
        as_root zypper --non-interactive install "$@"
    else
        warn "No supported package manager found (pacman, apt, dnf, zypper)"
        return 1
    fi
}

offer() {
    name="$1"
    shift
    if ask "$name is missing, install it?" y; then
        pkg_install "$@" && return 0
        warn "Failed to install $name"
    fi
    return 1
}

git_ok() {
    git --version >/dev/null 2>&1
}

newest_tag() {
    awk '{
        t = $0
        sub(/^.*\//, "", t)
        v = t
        sub(/^v/, "", v)
        if (v !~ /^[0-9]+(\.[0-9]+)*$/) next
        n = split(v, p, ".")
        k = ""
        for (i = 1; i <= 4; i++) k = k sprintf("%06d", (i <= n ? p[i] : 0))
        printf "%s%02d %s\n", k, n, t
    }' | sort | tail -n 1 | cut -d " " -f 2
}

latest_release() {
    has curl || return 0
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

install_git() {
    tag=$(latest_release)
    [ -n "$tag" ] || tag=$(git ls-remote --tags --refs "$url.git" | newest_tag)
    if [ -n "$tag" ]; then
        say "Cloning Tachytome $tag into $target..."
        git clone -q --no-checkout "$url.git" "$target"
        git -C "$target" -c advice.detachedHead=false checkout -q "$tag"
    else
        say "No release found, cloning master into $target..."
        git clone -q "$url.git" "$target"
    fi
}

install_archive() {
    has curl || die "curl is needed to download Tachytome"
    has tar  || die "tar is needed to extract Tachytome"
    tag=$(latest_release)
    [ -n "$tag" ] || tag=$(curl -fsSL "https://api.github.com/repos/$repo/tags?per_page=100" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' | newest_tag)
    ref="refs/heads/master"
    name="master"
    if [ -n "$tag" ]; then
        ref="refs/tags/$tag"
        name="$tag"
    fi
    say "Downloading Tachytome $name into $target..."
    tmp=$(mktemp -d)
    if ! curl -fsSL -o "$tmp/tachytome.tar.gz" "$url/archive/$ref.tar.gz"; then
        rm -rf "$tmp"
        die "Failed to download $url/archive/$ref.tar.gz"
    fi
    mkdir -p "$target"
    tar -xzf "$tmp/tachytome.tar.gz" --strip-components=1 -C "$target"
    rm -rf "$tmp"
}

case "$(uname -s)" in
    Darwin) platform="macos" ;;
    *)      platform="linux" ;;
esac

mpv_found=false
if has mpv || { [ "$platform" = "macos" ] && [ -d "/Applications/mpv.app" ]; }; then mpv_found=true; fi

if [ -n "${MPV_HOME:-}" ]; then
    mpv_dir="$MPV_HOME"
elif [ "$platform" = "linux" ] && [ "$mpv_found" = false ] && has flatpak && flatpak info io.mpv.Mpv >/dev/null 2>&1; then
    mpv_dir="$HOME/.var/app/io.mpv.Mpv/config/mpv"
    mpv_found=true
else
    mpv_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
fi

[ "$mpv_found" = true ] || warn "mpv not found, install it from https://mpv.io/installation"

target="$mpv_dir/scripts/tachytome"

if [ -e "$target" ]; then
    say "Tachytome is already installed at $target"
    if ! ask "Reinstall it? The current install is moved out of the scripts dir first" n; then
        say "Nothing to do, use Update from the Tachytome menu to update it"
        exit 0
    fi
    backup="$mpv_dir/tachytome-backup-$(date +%Y%m%d%H%M%S)"
    mv "$target" "$backup"
    say "Moved the current install to $backup"
fi

mkdir -p "$mpv_dir/scripts"

if git_ok || { offer git git && git_ok; }; then
    install_git
else
    say "Installing without git, Update will download releases from GitHub"
    install_archive
fi

if ! has ffmpeg; then
    offer FFmpeg ffmpeg || warn "Tachytome needs FFmpeg, install it before rendering"
fi

if [ "$platform" = "linux" ] && ! has gio && ! has trash-put && ! has trash; then
    offer trash-cli trash-cli || warn "Trash Source needs gio or trash-cli"
fi

say ""
say "Tachytome is installed at $target"
say "Restart mpv and press t to open the Tachytome menu"
