# modules/git-ecosystem.sh

Ставит `gh` (git-delta уже ставится модулем `modules/cli-tools.sh`, здесь
не дублируется). У gh нет пакета в стандартных репах — свой репозиторий
на `cli.github.com`, метод подключения различается по `OS_FAMILY`:
apt-keyring + sources.list для debian, `dnf/yum-config-manager
--add-repo` для rhel (dnf и yum — два разных набора команд). Идемпотентен
(пропускает всё, если `gh` уже в PATH). Требует `scripts/lib/os-detect.sh`.

**Известный баг (найден на Fedora 44 в WSL)**: начиная с Fedora 41 `dnf`
— это симлинк на `dnf5`, у которого плагин `config-manager` имеет
принципиально другой CLI: подкоманда `addrepo --from-repofile=<url>`
вместо флага `--add-repo <url>`. Пакета `dnf-command(config-manager)`
в dnf5 тоже не существует отдельно (config-manager встроен). Падало с
`Unknown argument "--add-repo" for command "config-manager"`. Исправлено
определением `dnf --version | grep '^dnf5'` и веткой под новый синтаксис;
dnf4-ветка (Fedora ≤40, CentOS Stream 9) сохранена как fallback.

**Тестирование**: на Ubuntu 24.04, Fedora 39 (dnf4), Fedora 44/WSL (dnf5),
CentOS Stream 9 (обе ветки apt/dnf; yum-ветка для CentOS 7 не
тестировалась вживую, но синтаксически проверена).
