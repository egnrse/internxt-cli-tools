# Tools for [internxt-cli](https://github.com/internxt/cli)


maybe:
- rclone backend (there is a PR for it: https://github.com/rclone/rclone/pull/8556)
- backup folders script (kinda  done)
- upload folders wrapper

## zsh completion
Some simple zsh completions: [\_internxt-zsh-completion](./_internxt-zsh-completion). Needs to be loaded into zsh.

Eg with:
```sh
fpath+=("$HOME/.config/zsh/completions/")
autoload -Uz compinit && compinit   # load completions
```
(might be included [upstream](https://github.com/internxt/cli/pull/330) at some point)

## simple backup shell script
[cloudBackup.sh](./cloudBackup.sh): does support `-h|--help`
