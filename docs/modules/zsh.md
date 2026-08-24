# modules/zsh.sh

Устанавливает zsh (через `os::pkg_install`), oh-my-zsh (неинтерактивно:
`RUNZSH=no CHSH=no`), Powerlevel10k и три внешних плагина
(zsh-autosuggestions, fast-syntax-highlighting, zsh-completions) через
`git clone --depth=1` в `$ZSH_CUSTOM`, пишет `~/.zshrc` из `config/zshrc`
(с бэкапом старого файла при отличии — сравнение через `cmp`; т.к.
`diffutils` не всегда стоит в минимальных образах, модуль сам ставит его
перед сравнением через `os::pkg_install diffutils`, идемпотентно) и
опционально делает zsh login-shell'ом по умолчанию через `chsh` — вопрос
задаётся через `/dev/tty` (`zsh::_want_default_shell`) по схеме из
"Механизм конфигурации" в CLAUDE.md, с env-override
`ZSH_DEFAULT_SHELL=yes|no` и безопасным дефолтом "no" без интерактива.

Требует зависимость `scripts/lib/os-detect.sh` (использует
`os::pkg_install`) — подключать оба через `source` в этом порядке.
Идемпотентен: повторный запуск ничего не переустанавливает и не трогает
уже применённый login-shell (проверка через `getent passwd`, а не
`$SHELL`, т.к. переменная не обновляется до перелогина).

**Тестирование**: end-to-end в контейнерах Ubuntu 24.04 и Fedora 39,
включая двойной запуск для проверки идемпотентности.
