# .krimsnrc

*(возможное короткое название: `.knrc`)*

Набор скриптов для быстрой настройки unix-окружения на Ubuntu, Debian,
Fedora и CentOS: zsh + oh-my-zsh + Powerlevel10k (+ Nerd Font-шрифты),
tmux (+ TPM, tmux-resurrect, tmux-continuum), git-экосистема (gh),
docker и набор CLI-утилит (полный список — в [CLAUDE.md](CLAUDE.md)).

## Быстрый старт

```bash
curl -fsSL https://raw.githubusercontent.com/KrimsN/dotfiles-setup/master/install.sh | bash
```

Скрипт сам поставит `git`/`curl`, если их ещё нет, склонирует репозиторий
и спросит, что устанавливать (или поставит всё — по умолчанию).

Из уже склонированного репозитория — то же самое:

```bash
./install.sh
```

Без вопросов, сразу всё:

```bash
./install.sh --yes
```

Только конкретные модули:

```bash
DOTFILES_MODULES="base zsh tmux" ./install.sh
```

## Статус

Все модули реализованы и протестированы на Ubuntu, Debian, Fedora и
CentOS (Docker/WSL). Подробности реализации, тестирования и принятые
решения — в [CLAUDE.md](CLAUDE.md).
