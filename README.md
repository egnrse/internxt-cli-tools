# Tools for [internxt-cli](https://github.com/internxt/cli)


maybe:
- rclone backend ([create a new backend](https://github.com/rclone/rclone/blob/master/CONTRIBUTING.md#writing-a-new-backend), written in go) (does already  exist https://github.com/rclone/rclone/pull/8556)
- backup folders script
- upload folders wrapper

## zsh completions
Some simple zsh completions: [\_internxt-zsh-completion](./_internxt-zsh-completion). Needs to be loaded into zsh.

Eg with:
```sh
fpath+=("$HOME/.config/zsh/completions/")
autoload -Uz compinit && compinit   # load completions
```

## backup shell script
unfinished script: [cloudBackup.sh](./cloudBackup.sh)
