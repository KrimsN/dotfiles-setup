```
    █████   ████            ███                          ██████   █████
   ░░███   ███░            ░░░                          ░░██████ ░░███
    ░███  ███    ████████  ████  █████████████    █████  ░███░███ ░███  ████████   ██████
    ░███████    ░░███░░███░░███ ░░███░░███░░███  ███░░   ░███░░███░███ ░░███░░███ ███░░███
    ░███░░███    ░███ ░░░  ░███  ░███ ░███ ░███ ░░█████  ░███ ░░██████  ░███ ░░░ ░███ ░░░
    ░███ ░░███   ░███      ░███  ░███ ░███ ░███  ░░░░███ ░███  ░░█████  ░███     ░███  ███
 ██ █████ ░░████ █████     █████ █████░███ █████ ██████  █████  ░░█████ █████    ░░██████
░░ ░░░░░   ░░░░ ░░░░░     ░░░░░ ░░░░░ ░░░ ░░░░░ ░░░░░░  ░░░░░    ░░░░░ ░░░░░      ░░░░░░
        unix-окружение в одну команду: zsh · tmux · nvim · p10k
```

# .krimsnrc

*(короткое название: `.knrc`)*

[![Ubuntu](https://github.com/KrimsN/krimsnrc/actions/workflows/test-ubuntu.yml/badge.svg)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-ubuntu.yml)
[![Debian](https://github.com/KrimsN/krimsnrc/actions/workflows/test-debian.yml/badge.svg)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-debian.yml)
[![Fedora](https://github.com/KrimsN/krimsnrc/actions/workflows/test-fedora.yml/badge.svg)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-fedora.yml)
[![CentOS](https://github.com/KrimsN/krimsnrc/actions/workflows/test-centos.yml/badge.svg)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-centos.yml)

Набор скриптов для быстрой настройки unix-окружения на Ubuntu, Debian,
Fedora и CentOS: zsh + oh-my-zsh + Powerlevel10k (+ Nerd Font-шрифты),
tmux (+ TPM, tmux-resurrect, tmux-continuum), git-экосистема (gh),
docker и набор CLI-утилит (полный список — в [CLAUDE.md](CLAUDE.md)).

## Быстрый старт

```bash
curl -fsSL https://raw.githubusercontent.com/KrimsN/krimsnrc/master/install.sh | bash
```

Для самой команды `curl` нужен заранее (обычно он уже есть в системе);
если это не так — установите его вручную первым шагом. А вот `git` для
запуска через `curl | bash` не требуется — скрипт при необходимости
доставит его сам перед клонированием репозитория, спросит, что
устанавливать (или поставит всё — по умолчанию).

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
CentOS (Docker/WSL). На каждый push/PR в `master` GitHub Actions
дополнительно прогоняет полный `install.sh` (дважды, на idempotency)
в контейнерах Ubuntu 24.04, Debian 12, Fedora (latest) и CentOS
Stream 9 — статус см. в бейджах выше. CentOS 7 (yum-fallback) в CI не
включён из-за протухших зеркал EOL-дистрибутива — поддерживается
только для ручного тестирования через `scripts/test-module.sh`.
Подробности реализации, тестирования и принятые решения — в
[CLAUDE.md](CLAUDE.md).
