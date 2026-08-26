# scripts/lib/os-detect.sh

Определяет `OS_ID`, `OS_VERSION_ID`, `OS_FAMILY` (debian|rhel) и `PKG_MANAGER`
(apt|dnf|yum) через `/etc/os-release` + наличие бинарника dnf/yum. Даёт
обёртки `os::pkg_update`, `os::pkg_upgrade` (обновить индекс + накатить
обновления установленных пакетов — используется `modules/base.sh`) и
`os::pkg_install`. Подключается через `source`,
при прямом запуске печатает результат детекции для отладки.

**Тестирование**: в контейнерах/WSL — Ubuntu 24.04, Debian 12, Fedora 39,
CentOS Stream 9 (dnf) и CentOS 7 (yum-fallback); неподдерживаемый
дистрибутив (проверено на Alpine) даёт понятную ошибку и код возврата 1.
