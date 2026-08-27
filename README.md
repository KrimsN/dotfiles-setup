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
docker и набор CLI-утилит (полный список — в
[docs/PROJECT.md](docs/PROJECT.md)).

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

## Диагностика

Вместе с модулями `install.sh` ставит команду `knrc` (в
`~/.local/bin`). Проверить, что на машине реально встало, а что нет:

```bash
knrc doctor
```

Строка на проверку со статусом `ok` / `отсутствует` / `сломано`,
итоговый счётчик и ненулевой код возврата при проблемах — команду можно
ставить шагом в CI. Она ничего не чинит и не устанавливает; чтобы
доустановить недостающее, нужен обычный `install.sh`. Сузить набор
проверок — `knrc doctor --modules=zsh,tmux`. Подробности — в
[docs/modules/doctor.md](docs/modules/doctor.md).

## Обновление

Подтянуть последнюю версию `.knrc` и переустановить новые модули:

```bash
knrc update
```

Делает `git pull --ff-only` в локальном клоне и перезапускает
`install.sh`. Посмотреть, что подтянется, ничего не меняя: `knrc update
--dry-run`. Отказывается обновлять, если в клоне есть незакоммиченные
правки. Подробности — в [docs/modules/update.md](docs/modules/update.md).

## Откат

Вернуть машину к состоянию до установки:

```bash
knrc uninstall
```

Команда сначала печатает полный план — что восстановит из бэкапов, что
удалит, что вернёт на место, — и только потом спрашивает подтверждение
(нужно ввести `yes` целиком). Посмотреть план, ничего не меняя:
`knrc uninstall --dry-run`. Для автоматизации есть `--force`; сам по
себе `NONINTERACTIVE=1` подтверждением не считается — без явного флага
команда откажется работать.

Пакеты, установленные пакетным менеджером, **не удаляются**: они могли
стоять до нас или быть нужны системе. Вместо этого в конце печатается
список того, что осталось, с готовой командой удаления. Ваши
`*.local`-файлы тоже остаются нетронутыми. Подробности — в
[docs/modules/uninstall.md](docs/modules/uninstall.md).

## Харденинг SSH (опционально)

Отдельная команда, не часть установки и не часть отката — только по
явному запросу, после того как вы убедились, что вход по SSH-ключу
работает:

```bash
knrc harden-ssh
```

Отключает root-логин и вход по паролю в `sshd_config` этой машины.
Печатает план и спрашивает подтверждение так же, как `knrc uninstall`;
свои `--dry-run` и `--rollback`. Подробности — в
[docs/modules/harden-ssh.md](docs/modules/harden-ssh.md).

## Статус

Все модули реализованы и протестированы на Ubuntu, Debian, Fedora и
CentOS (Docker/WSL). На каждый push/PR в `master` GitHub Actions
дополнительно прогоняет полный `install.sh` (дважды, на idempotency)
в контейнерах Ubuntu 24.04, Debian 12, Fedora (latest) и CentOS
Stream 9 — статус см. в бейджах выше. CentOS 7 (yum-fallback) в CI не
включён из-за протухших зеркал EOL-дистрибутива — поддерживается
только для ручного тестирования через `scripts/test-module.sh`.
Полный список программ, история решений по составу и таблица модулей
с покрытием тестами — в [docs/PROJECT.md](docs/PROJECT.md); детали
реализации каждого модуля — в `docs/modules/`.
