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

`cli-tools.sh` использует общую `github_release::install` вместо своей
копии; порядок `source`: `scripts/lib/github-release.sh` нужно
подключать перед `cli-tools.sh` и `extras.sh`.
