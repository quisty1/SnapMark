# SnapMark

Нативный локальный скриншотер для macOS 14+ / Apple Silicon. Native, local screenshot utility for macOS 14+ / Apple Silicon.

## Сборка из репозитория

```sh
git clone https://github.com/quisty1/SnapMark.git
cd SnapMark
./scripts/build-app.sh
```

Готовые `SnapMark.app` и `SnapMark.zip` появятся в `dist/`. Для сборки нужны Swift 6.2+ и Command Line Tools либо Xcode на Mac с Apple Silicon.

## Запуск

1. Распакуй `SnapMark.zip` и перенеси `SnapMark.app` в папку «Программы» или другое постоянное место.
2. Открой приложение. SnapMark работает через значок рамки в строке меню, без иконки в Dock.
3. Нажми «Сделать скриншот» или `⌃⇧2`. При первом захвате выдай приложению доступ в **Системные настройки → Конфиденциальность и безопасность → Запись экрана**. Название раздела может отличаться в разных версиях macOS. Если SnapMark отсутствует в списке, нажми «+» и выбери именно текущий `SnapMark.app`. Если система попросит, нажми «Завершить и открыть снова». Локальная подпись меняется при пересборке: для обновлённой сборки может потребоваться удалить старую запись SnapMark и добавить текущий файл заново.
4. Выдели область. Пробел переключает на выбор окна. В меню также доступны окно и весь выбранный дисплей.
5. Добавь пометки и нажми **Копировать** (`⌘C`) или **Сохранить** (`⌘S`). Редактор закроется после успешного завершения.

«Попробовать редактор» на стартовом экране открывает учебное изображение без разрешения на захват экрана.

## Редактирование

- Толщина линий по умолчанию — 12 пикселей, примерно середина шкалы 1–24. У кнопок и настроек есть подсказки при наведении на русском и английском.
- Панель: выделение, перо, маркер, линия, стрелка, прямоугольник, эллипс, текст, номер шага, блюр, пикселизация, непрозрачная заливка, обрезка.
- Выбери объект инструментом выделения, чтобы переместить его. Нижний правый маркер изменяет размер. Двойной щелчок по тексту открывает ввод; Enter завершает ввод, Esc отменяет его. Пустой текст удаляет существующую надпись.
- Цвет, толщина, размер текста, полужирное начертание, заливка и сила эффекта доступны в нижней строке панели для соответствующего инструмента.
- `⌘Z` отменяет, `⌘⇧Z` повторяет, Delete удаляет выделенный объект.
- Прокрутка сдвигает холст; `⌥` + прокрутка или жест сведения/разведения меняет масштаб. Пробел + перетаскивание также сдвигает холст.
- `Esc` закрывает захват/редактор без записи в историю. При активном текстовом поле сохраняются обычные сочетания для работы с текстом.
- PNG сохраняет исходное разрешение и прозрачность. JPEG выбирается в диалоге сохранения и использует белую подложку для прозрачных областей.

## OCR, закрепление и история

OCR обрабатывает итоговое изображение после обрезки и применения пометок/масок через системный Vision. Русский и английский распознаются локально при наличии поддержки в macOS. Копирование текста не закрывает редактор. Закрепление завершает редактирование и открывает готовое изображение поверх других окон; закреплённые окна можно перемещать, масштабировать, копировать и закрывать.

В историю попадают только завершённые снимки после копирования, сохранения или закрепления. Хранятся готовый PNG, его миниатюра и индекс; исходный кадр и объекты редактирования на диск не записываются. В истории можно добавить новые пометки поверх готовой картинки; старый блюр, текст и фигуры уже нельзя убрать. По умолчанию хранятся 100 снимков, лимит меняется в настройках. Данные находятся в `~/Library/Application Support/SnapMark`.

Язык: системный, русский или английский. Тема: системная, светлая или тёмная. Сочетание захвата переназначается в настройках. Если зарегистрировать новое сочетание не удалось, сохраняется предыдущее; зарезервированные системой сочетания могут перехватываться самой macOS.

Первая версия не содержит сети, аккаунтов, облака, записи видео и длинных снимков с прокруткой. Область захвата ограничена одним дисплеем; окно снимается как отдельное окно, без перекрывающих его приложений. Незавершённые сеансы и закрепления не восстанавливаются после перезапуска. Сборка подписана локально для личного использования, без Developer ID / нотариализации.

## Сборка и проверки

Нужны macOS 14+, Apple Silicon, Swift 6.2+ и Command Line Tools (`xcode-select --install`) либо Xcode. Зависимостей из сети нет.

```sh
./scripts/test.sh
./scripts/build-app.sh /absolute/path/to/output
```

`test.sh` запускает проверки модели/геометрии/рендера/реального файлового хранилища, затем нативные проверки жизненного цикла окон и настоящий Vision OCR. Для нативной части требуется графическая сессия macOS; окна проверки могут кратковременно появляться. Используется автономный Swift-раннер, поскольку поставка Command Line Tools может не содержать XCTest/Swift Testing. Любая проваленная проверка возвращает ненулевой код.

Пакет собирается через Swift Package Manager; `build-app.sh` создаёт и проверяет локальную подпись `.app`, создаёт иконку и ZIP. Для разработки можно открыть `Package.swift` в Xcode. `SnapMarkCore` содержит модель, рендерер и историю; `SnapMark` — захват, холст, интерфейс и системные интеграции. Контрольные сценарии и результаты этой сборки перечислены в `QA.md`.

---

## English quick start

Unzip `SnapMark.zip`, move `SnapMark.app` to Applications or another permanent location, and open it. Use the menu-bar viewfinder icon or **Control–Shift–2** to capture an area. On first capture, grant Screen Recording access in **System Settings → Privacy & Security**, then retry or relaunch if macOS requests it. If SnapMark is missing from the list, use the + button to add the current SnapMark.app. A rebuilt ad-hoc app may require removing its old permission entry and adding the new app again. **Try the editor** opens a sample image without screen-capture permission.

Space switches to window selection. Display capture is available in the menu. Choose a tool, annotate, then **Command–C** to copy or **Command–S** to save and close. **Escape** cancels without creating a history entry. Undo/redo: **Command–Z / Command–Shift–Z**. Select an object to move or resize using its bottom-right handle; double-click text to edit. Scroll pans; Option–scroll or pinch zooms. Text fields retain normal text shortcuts.

The lower toolbar changes color, width, font size/weight, fill or blur/pixelation intensity. PNG is the default; choose JPEG in the save dialog for an opaque white background. OCR runs locally on the rendered/cropped image, including masks. Copying recognized text leaves the editor open. Pinning opens a movable/resizable image above other windows and finishes the edit.

Only completed, flattened images are stored in local history; originals and editable objects are never saved. Reopening history allows new annotations, while previous annotations cannot be removed. History defaults to 100 images and is adjustable in Settings. Language and appearance follow the system unless overridden. No network services, accounts or telemetry are included.

Build with `./scripts/build-app.sh /absolute/output/path`; run checks with `./scripts/test.sh`. Requires Swift 6.2+, Command Line Tools or Xcode, and a graphical macOS session for native checks. This is an Apple Silicon personal-use build with an ad-hoc signature, not a notarized public release. Capture regions stay within one display. Unfinished edits and pinned windows do not survive relaunch.
