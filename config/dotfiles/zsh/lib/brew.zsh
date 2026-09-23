if [[ -x /opt/homebrew/bin/brew ]]; then
  if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
  fi
  path=(
    "$HOME/.opencode/bin"
    "$HOME/.config/tokenmaxxing/bin"
    "$HOME/.local/bin"
    "/opt/homebrew/opt/node@24/bin"
    "/opt/homebrew/opt/curl/bin"
    "$HOME/.local/share/google-cloud-sdk/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    $path
  )
fi
