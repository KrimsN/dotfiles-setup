# scripts/lib/github-release.sh

Вынесено из `cli-tools.sh` в общую библиотеку (та же причина, что и с
EPEL: понадобилось второй раз, для fastfetch в `extras.sh`).
`github_release::install <repo> <asset_regex> <inner_path_glob>
<target_name>` — резолвит последний релиз через GitHub API, качает и
распаковывает архив, кладёт бинарник в `/usr/local/bin`.
`github_release::arch_rust` / `arch_go` — маппинг `uname -m` на нужный
стиль именования ассетов (Rust-проекты: x86_64/aarch64; Go/goreleaser:
amd64/arm64).

**Важный нюанс**: `inner_path_glob` матчится через `find -path
"*<glob>"` по полному пути внутри архива, а не только по имени файла
(было `-name`) — обнаружено на fastfetch, у которого бинарник
`usr/bin/fastfetch` и bash-completion `usr/share/.../fastfetch`
называются одинаково, и `-name` с `head -n1` мог случайно подсунуть
скрипт-completion вместо бинарника. Для новых вызовов передавать
что-то вроде `"usr/bin/tool"`, а не просто `"tool"`, если есть шанс
коллизии имён внутри архива.

**Баг, воспроизведённый на практике (2026-08-25, WSL Fedora)**:
`cli::install_zoxide` вызывался с `inner_path_glob="zoxide"` — глоб
`*zoxide` матчится по подстроке, а не по границе пути, поэтому он
совпал не только с самим бинарником `zoxide`, но и с
`completions/_zoxide` (zsh-completion скрипт из того же архива, путь
которого тоже оканчивается на "zoxide"). `find` не гарантирует
порядок обхода, и на затронутой машине `head -n1` подсунул именно
completion-скрипт — в `/usr/local/bin/zoxide` оказался текстовый файл
с zsh-синтаксисом (`autoload`, `compdef`, `$+functions[...]`) вместо
ELF-бинарника. При запуске (`zoxide init zsh` в `.zshrc`) шелл пытался
исполнить этот файл как обычный скрипт и падал с ворохом ошибок
`autoload: command not found` / `arithmetic syntax error` /
`compdef: command not found`.

**Фикс**: все вызовы `github_release::install` в `cli-tools.sh`
теперь передают `inner_path_glob` с ведущим `/` (`/zoxide`, `/eza`,
`/delta`, `/rg`, `/fd`, `/fzf`, `/bat`, `/curlie`) — так `*<glob>`
матчится только по полному компоненту пути (граница — разделитель
`/`), и `_zoxide` больше не совпадает с `/zoxide`. На уже сломанной
установке лечится так: `sudo rm -f /usr/local/bin/zoxide`, затем
повторный запуск `install.sh` — он идемпотентен и доустановит только
отсутствующий zoxide с исправленным глобом.

`cli-tools.sh` использует общую `github_release::install` вместо своей
копии; порядок `source`: `scripts/lib/github-release.sh` нужно
подключать перед `cli-tools.sh` и `extras.sh`.
