# .knrc: авто-подключение tmux к существующей сессии.
# Устанавливается модулем modules/tmux.sh в
# ~/.config/knrc/tmux-autoattach.sh — не редактировать
# исходник на месте установки, правки перезапишутся при повторном
# запуске установки.
#
# Голый `tmux` без аргументов подключается к уже существующей сессии
# (последней активной), если она есть, иначе создаёт новую. Если
# переданы явные аргументы (например `tmux new -s foo`, `tmux kill-server`)
# — поведение tmux не переопределяется.
tmux() {
  if [ -n "${TMUX:-}" ]; then
    command tmux "$@"
    return
  fi
  if [ "$#" -eq 0 ]; then
    command tmux attach-session || command tmux new-session
  else
    command tmux "$@"
  fi
}
