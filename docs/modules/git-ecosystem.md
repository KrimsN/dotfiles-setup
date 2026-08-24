# modules/git-ecosystem.sh

Ставит `gh` (git-delta уже ставится модулем `modules/cli-tools.sh`, здесь
не дублируется). У gh нет пакета в стандартных репах — свой репозиторий
на `cli.github.com`, метод подключения различается по `OS_FAMILY`:
apt-keyring + sources.list для debian, `dnf/yum-config-manager
--add-repo` для rhel (dnf и yum — два разных набора команд). Идемпотентен
(пропускает всё, если `gh` уже в PATH). Требует `scripts/lib/os-detect.sh`.

**Тестирование**: на Ubuntu 24.04, Fedora 39, CentOS Stream 9 (обе ветки
— apt и dnf; yum-ветка для CentOS 7 не тестировалась вживую, но
синтаксически проверена).
