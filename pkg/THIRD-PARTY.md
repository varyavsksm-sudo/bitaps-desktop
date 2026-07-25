# Сторонние компоненты в сборке bitaps VPN

## Xray-core

В десктопные сборки (Windows/Linux/macOS) рядом с исполняемым файлом кладётся бинарь
**Xray-core** — им поднимается сам VPN-туннель.

* Проект: https://github.com/XTLS/Xray-core
* Версия: **v26.3.27** (закреплена; обновление — только вместе с контрольной суммой в CI)
* Лицензия: **Mozilla Public License 2.0** — https://github.com/XTLS/Xray-core/blob/main/LICENSE
* Изменений в исходный код не вносилось: используется официальный релизный бинарь,
  скачиваемый в CI с проверкой SHA-256 из официального файла `.dgst`.

Контрольные суммы (SHA-256) закреплённых архивов:

| Платформа | Архив | SHA-256 |
|---|---|---|
| Windows x64 | `Xray-windows-64.zip` | `d004c39288ce9ada487c6f398c7c545f7d749e44bdfdd59dbc9f865afba4e1ad` |
| Linux x64 | `Xray-linux-64.zip` | `23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae` |
| macOS arm64 | `Xray-macos-arm64-v8a.zip` | `2e93a67e8aa1936ecefb307e120830fcbd4c643ab9b1c46a2d0838d5f8409eaf` |

### Почему именно Xray, а не sing-box

Узлы «белого списка» ходят транспортом **xhttp** (SplitHTTP с GET-аплинком) через CDN.
В официальном sing-box такого транспорта нет — он есть только в Xray. Без Xray эти узлы
в приложении были бы недоступны.

### Ручная сборка macOS

CI macOS не собирает (см. комментарий в `.github/workflows/build.yml`). При ручной сборке
положите бинарь рядом с исполняемым файлом внутри пакета — `bitaps_vpn.app/Contents/MacOS/xray` —
и подпишите его тем же сертификатом, что и само приложение, иначе Gatekeeper не даст его запустить.
