# Tools for [internxt-cli](https://github.com/internxt/cli)


maybe:
- rclone backend (there is a PR for it: https://github.com/rclone/rclone/pull/8556)
- backup folders script
- upload folders wrapper

## zsh completions
Some simple zsh completions: [\_internxt-zsh-completion](./_internxt-zsh-completion). Needs to be loaded into zsh.

Eg with:
```sh
fpath+=("$HOME/.config/zsh/completions/")
autoload -Uz compinit && compinit   # load completions
```

## simple backup shell script
[cloudBackup.sh](./cloudBackup.sh)
