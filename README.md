# Krasava SwiftUI

Нативное приложение расписания РТУ МИРЭА на SwiftUI для iOS 26.

Лёгкая альтернатива [krasava-app](https://github.com/Vibe-Moments-Technologies/krasava-app):
только расписание, мини-календарь, заметки, напоминания и виджеты. Всё
оформление — системное, на Liquid Glass.

> Приложение неофициальное. Расписание загружается из открытых источников
> РТУ МИРЭА и не является продуктом университета.

---

## Что внутри

| Блок | Состояние |
|---|---|
| Разбор iCal-фида, недели семестра, чётность | ✅ |
| Кэш с TTL и защитой от затирания пустым ответом | ✅ |
| Лента дня, карточки, прогресс пары и перемены | ✅ |
| Мини-календарь (неделя / две недели) | ✅ |
| Поиск и выбор расписания | ✅ |
| Заметки к паре и предмету | ✅ |
| Гибридные типы занятий и свои цвета | ✅ |
| Дифф «что изменилось» | ✅ |
| Скрытие предметов и доп. занятий | ✅ |
| Виджет (small / medium / large) | ✅ |
| Уведомления, Live Activity, Siri, Spotlight | ⏳ следующие этапы |

Подробности решений — в [docs/CONCEPT.md](docs/CONCEPT.md).

### Чего здесь нет и не будет

Игр, карт корпусов, конспектов, задач, сравнения расписаний, свободных
аудиторий, тематических скинов, аналитики и любых сторонних SDK.

Приложение делает **ровно два** сетевых запроса, оба GET, оба на
`schedule-of.mirea.ru`. Ноль зависимостей: `Package.resolved` отсутствует,
потому что отсутствуют пакеты.

---

## Требования

- Xcode 26 (SDK iOS 26)
- iOS 26.0+
- Swift 6

## Сборка

```bash
# Открыть проект
open KrasavaSwiftUI.xcodeproj

# Тесты
xcodebuild test \
  -project KrasavaSwiftUI.xcodeproj \
  -scheme KrasavaSwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Сборка для устройства без подписи
xcodebuild build \
  -project KrasavaSwiftUI.xcodeproj \
  -scheme KrasavaSwiftUI \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## Структура

```
Shared/               Ядро: домен и данные. Компилируется и в приложение, и в виджет
  Domain/             Чистые функции: парсер, недели, слоты, дифф, типы, заметки
  Data/               Сеть, кэш, хранилища, снапшот для виджета
  Localization/       Подписи с подстановкой чисел
KrasavaSwiftUI/       Приложение: экраны, дизайн-система, ресурсы
KrasavaWidget/        Расширение виджетов
KrasavaSwiftUITests/  Тесты домена
Support/              Info.plist и entitlements (вне synchronized-групп)
tools/                versioning.py — единственный источник версий
```

`Shared` подключён к обоим таргетам через `PBXFileSystemSynchronizedRootGroup`:
новый файл в каталоге попадает в сборку сам, править `project.pbxproj` не нужно.

## Хранение данных

| Что | Где | Бэкапится |
|---|---|---|
| Заметки | Application Support | да |
| Переопределения типов и цветов | Application Support | да |
| Выбранное расписание | Application Support | да |
| Кэш расписания | Caches | нет |
| Снапшот для виджета | App Group | нет |

Кэш вынесен в Caches осознанно: он восстанавливается одним запросом и не
должен раздувать резервную копию.

## Версии и релизы

Версия живёт только в файле [`VERSION`](VERSION). Каналы выводятся из тега:

| Канал | Триггер | Формат |
|---|---|---|
| stable | тег `v26.1.0` | `26.1.0` |
| beta / rc | тег `v26.1.0-beta.3` | `26.1.0-beta.3` |
| dev | push в `main` | `26.1.0-dev.N` (rolling `preview`) |

`CFBundleVersion` — epoch-секунды, считаются один раз в resolve-джобе и
передаются в `xcodebuild` как `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
Файлы проекта при сборке не патчатся.

Сборки выходят без подписи: IPA нужно переподписать любым инструментом
(AltStore, GBox, Feather, ESign, Sideloadly). App Group уже заявлена в
entitlements, поэтому виджет продолжит работать после переподписи.

## Лицензия

[GPL-3.0](LICENSE) — как производная работа от оригинального приложения.