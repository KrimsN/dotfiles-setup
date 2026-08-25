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

[![Ubuntu 24.04](https://img.shields.io/github/actions/workflow/status/KrimsN/krimsnrc/test-ubuntu.yml?label=Ubuntu%2024.04&logo=ubuntu&logoColor=white&labelColor=E95420&style=flat)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-ubuntu.yml)
[![Debian 12](https://img.shields.io/github/actions/workflow/status/KrimsN/krimsnrc/test-debian.yml?label=Debian%2012&logo=debian&logoColor=white&labelColor=A81D33&style=flat)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-debian.yml)
[![Fedora Latest](https://img.shields.io/github/actions/workflow/status/KrimsN/krimsnrc/test-fedora.yml?label=Fedora%20Latest&logo=fedora&logoColor=white&labelColor=51A2DA&style=flat)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-fedora.yml)
[![CentOS Stream 9](https://img.shields.io/github/actions/workflow/status/KrimsN/krimsnrc/test-centos.yml?label=CentOS%20Stream%209&logo=centos&logoColor=white&labelColor=262577&style=flat)](https://github.com/KrimsN/krimsnrc/actions/workflows/test-centos.yml)
[![Lint](https://img.shields.io/github/actions/workflow/status/KrimsN/krimsnrc/lint.yml?label=Lint&logo=gnu-bash&logoColor=white&labelColor=4EAA25&style=flat)](https://github.com/KrimsN/krimsnrc/actions/workflows/lint.yml)

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
