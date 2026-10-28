# AnimeApp — аниме с русской озвучкой для iOS

Нативное iOS-приложение (SwiftUI, iOS 16+) для просмотра аниме с русской озвучкой и субтитрами.
Метаданные берутся из Shikimori, видео — из AniLibria и (по желанию) YummyAnime.
Проект собирается только в GitHub Actions: Mac не нужен.

> Эта ветка (`ios-anime`) — отдельное ответвление репозитория без истории Android-модуля Yume.
> Позже её можно перенести в отдельный репозиторий как `main`, workflow уже рассчитан на это.

## Возможности

- **Главная** — онгоинги, популярное, недавно обновлённые (свежие серии AniLibria), «Продолжить просмотр».
- **Каталог** — бесконечная прокрутка, фильтры по жанрам, году, сезону, типу и статусу, сортировка.
- **Поиск** с задержкой ввода (debounce) — по русскому и оригинальному названию.
- **Карточка тайтла** — постер, описание, рейтинг, жанры, студия, связанные и похожие тайтлы,
  выбор источника и озвучки, список серий с прогрессом.
- **Плеер** — AVPlayer: выбор качества (480/720/1080), полноэкранный режим, картинка в картинке,
  «Следующая серия», «Пропустить опенинг» (если источник отдаёт тайминги), сохранение позиции.
- **Расписание** выхода серий по дням недели (AniLibria).
- **Моё** — избранное, история и прогресс по сериям, всё хранится локально.
- Состояния загрузки, ошибок с кнопкой «Повторить» и пустых экранов. Тёмная тема.

## Источники данных

| Источник | Что берём | API |
|---|---|---|
| [Shikimori](https://shikimori.io/api/doc) | каталог, поиск, жанры, рейтинги, постеры, описания, похожие | GraphQL `POST /api/graphql`, REST `GET /api/animes/:id/similar` |
| [AniLibria](https://aniliberty.top/api/docs/v1) | релизы, серии, HLS 480/720/1080, тайминги опенинга, расписание | `GET /api/v1/app/search/releases`, `/anime/releases/{id}`, `/anime/releases/episodes/{id}`, `/anime/releases/latest`, `/anime/schedule/week` |
| [YummyAnime](https://api.yani.tv/swagger) | дополнительные озвучки и плееры | `GET /anime?shikimori_ids=`, `/search`, `/anime/{id}/videos` |

- Shikimori требует название приложения в `User-Agent` и ограничивает API до 5 запросов в секунду
  и 90 в минуту. Все запросы к нему идут через общий `RateLimiter`, который соблюдает оба окна.
- Тайтлы между источниками сопоставляются по ID Shikimori/MyAnimeList (AniLibria и YummyAnime их отдают),
  а если ID нет — по нормализованному названию и году выхода (`TitleMatcher`).
- YummyAnime отдаёт не прямые потоки, а официальные встраиваемые плееры (Kodik, Aksor, Alloha…),
  поэтому такие серии открываются во встроенном веб-плеере. Защиту и DRM приложение не обходит.

## Хранение данных: почему JSON-файл

Минимальная версия iOS — 16, а SwiftData есть только с iOS 17. Держать два хранилища
(SwiftData и Core Data) значит удвоить код. Данных мало (избранное, история, прогресс серий),
связей и сложных запросов нет, поэтому выбран один Codable-файл `library.json` в Application Support:
атомарная запись, отложенное сохранение во время просмотра, легко тестировать.

## Сборка через GitHub Actions

Workflow: [`.github/workflows/build.yml`](.github/workflows/build.yml), runner `macos-latest`.

1. Выбирает свежий стабильный Xcode, ставит XcodeGen и генерирует `AnimeApp.xcodeproj`
   из `project.yml` (сам проект в git не хранится).
2. Собирает тесты и прогоняет юнит-тесты на симуляторе iPhone.
3. Делает `xcodebuild archive` без подписи (`CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=""`).
4. Кладёт `AnimeApp.app` в `Payload/` и упаковывает в `AnimeApp.ipa`.
5. Загружает IPA как artifact, а при пуше тега `v*` прикрепляет к GitHub Release.

Сборка запускается на каждый push в `main` и `ios-anime`, на pull request и вручную
(**Actions → iOS - Build IPA → Run workflow**).

### Где скачать IPA

- **Последняя сборка:** вкладка **Actions** → последний зелёный запуск **iOS - Build IPA** →
  блок **Artifacts** → `AnimeApp-ipa` (zip, внутри `AnimeApp.ipa`).
- **Релиз:** создайте и запушьте тег, например `git tag v1.0.0 && git push origin v1.0.0`,
  и IPA появится на странице **Releases**. В этом репозитории Android-модуль тоже использует
  теги `v*`, поэтому для iOS берите номера, которые с ним не пересекаются (например, `v10.0.0`),
  или выносите проект в отдельный репозиторий.

## Установка через AltStore / Sideloadly

IPA не подписан — его подпишет AltStore или Sideloadly вашим Apple ID.

**AltStore**
1. Установите AltServer на компьютер и AltStore на iPhone ([altstore.io](https://altstore.io)).
2. Скачайте `AnimeApp.ipa` на iPhone (например, через Файлы).
3. В AltStore: **My Apps → +** → выберите `AnimeApp.ipa`.
4. С бесплатным Apple ID приложение нужно обновлять раз в 7 дней (AltStore делает это сам при наличии AltServer в сети).

**Sideloadly**
1. Установите [Sideloadly](https://sideloadly.io) на Windows или macOS и подключите iPhone кабелем.
2. Перетащите `AnimeApp.ipa` в окно, укажите Apple ID и нажмите **Start**.
3. На iPhone: **Настройки → Основные → VPN и управление устройством** → доверьте профилю разработчика.
   На iOS 16+ также включите **Настройки → Конфиденциальность → Режим разработчика**.

## Ключ YummyAnime

Документация YummyAnime требует публичный токен приложения в заголовке `X-Application`.
Без него приложение работает, просто источник YummyAnime скрыт.

1. Создайте приложение на <https://yummyani.me/dev/applications> и скопируйте публичный токен.
2. **Для сборки в CI:** репозиторий → **Settings → Secrets and variables → Actions → New repository secret**,
   имя `YUMMY_APP_TOKEN`, значение — токен. Workflow запишет его в `Config/Secrets.xcconfig` перед сборкой.
3. **Для локальной сборки на Mac:** `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig`
   и впишите токен. Файл в `.gitignore` и в git не попадает.

Токен попадает в `Info.plist` (`YummyAppToken`), это публичный ключ приложения, а не пароль пользователя.

## Структура

```
project.yml                 XcodeGen: таргеты, SPM-зависимость Nuke, схема
Config/                     xcconfig (секреты — вне git)
AnimeApp/
  App/                      точка входа, вкладки, сервисы
  Core/
    Networking/             HTTPClient, RateLimiter, ошибки
    Shikimori/              GraphQL-клиент и разбор ответов
    Sources/                протокол AnimeSource, TitleMatcher
      AniLibria/  Yummy/    реализации источников
    Storage/                LibraryStore (JSON)
    Models/  Util/
  Features/                 Home, Catalog, Search, Detail, Player, Schedule, Library (MVVM)
  UI/                       общие компоненты и состояния экранов
AnimeAppTests/              тесты парсинга (фикстуры — реальные ответы API), сопоставления, хранилища, лимитера
```

Единственная внешняя зависимость — [Nuke](https://github.com/kean/Nuke) для загрузки и кэширования постеров.
Видео воспроизводится нативным AVPlayer/AVKit.
