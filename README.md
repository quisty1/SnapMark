# SnapMark

[English](#english) · [Русский](#русский)

## English

SnapMark captures a region, window or display on Apple Silicon Macs running macOS 14 or later. Annotate the result, extract text with on-device Vision OCR, save it, or pin it above other windows.

### Build and open

Install Swift 6.2 or later with the macOS Command Line Tools or Xcode, then run:

```sh
git clone https://github.com/quisty1/snap-mark.git
cd snap-mark
./scripts/build-app.sh
open dist/SnapMark.app
```

The script produces `SnapMark.app` and `SnapMark.zip` in `dist/`. The app is signed locally for personal use. Grant Screen Recording access on first capture; macOS may require you to reauthorize a rebuilt app. **Try the editor** opens a sample without screen access.

### Capture and edit

Press **⌃⇧2** or use the menu bar icon. Press **Space** to switch from region to window selection; use the menu for display capture. Add arrows, shapes, text, step numbers, blur, pixelation, or a solid mask, then press **⌘C** to copy or **⌘S** to save. PNG preserves transparency; JPEG uses a white background. **Esc** cancels, **⌘Z** undoes, and **⌘⇧Z** redoes.

OCR processes the rendered, cropped image locally. Copying recognized text leaves the editor open; pinning finishes the edit. History saves only completed, flattened images, so earlier annotations cannot be removed in a reopened image. There are no accounts or cloud services. Regions stay within one display, and video or scrolling capture is outside the current scope.

Run `./scripts/test.sh` for core and native checks. Native window and OCR checks require a graphical macOS session.

## Русский

Нативный локальный скриншотер для macOS 14+ / Apple Silicon.

### Сборка из репозитория

```sh
git clone https://github.com/quisty1/snap-mark.git
cd snap-mark
./scripts/build-app.sh
```

Готовые `SnapMark.app` и `SnapMark.zip` появятся в `dist/`. Для сборки нужны Swift 6.2+ и Command Line Tools либо Xcode на Mac с Apple Silicon.

### Запуск

1. Распакуй `SnapMark.zip` и перенеси `SnapMark.app` в папку «Программы» или другое постоянное место.
2. Открой приложение. SnapMark работает через значок рамки в строке меню, без иконки в Dock.
3. Нажми «Сделать скриншот» или `⌃⇧2`. При первом захвате выдай приложению доступ в **Системные настройки → Конфиденциальность и безопасность → Запись экрана**. Название раздела может отличаться в разных версиях macOS. Если SnapMark отсутствует в списке, нажми «+» и выбери именно текущий `SnapMark.app`. Если система попросит, нажми «Завершить и открыть снова». Локальная подпись меняется при пересборке: для обновлённой сборки может потребоваться удалить старую запись SnapMark и добавить текущий файл заново.
4. Выдели область. Пробел переключает на выбор окна. В меню также доступны окно и весь выбранный дисплей.
5. Добавь пометки и нажми **Копировать** (`⌘C`) или **Сохранить** (`⌘S`). Редактор закроется после успешного завершения.

«Попробовать редактор» на стартовом экране открывает учебное изображение без разрешения на захват экрана.

### Редактирование

- Толщина линий по умолчанию — 12 пикселей, примерно середина шкалы 1–24. У кнопок и настроек есть подсказки при наведении на русском и английском.
- Панель: выделение, перо, маркер, линия, стрелка, прямоугольник, эллипс, текст, номер шага, блюр, пикселизация, непрозрачная заливка, обрезка.
- Выбери объект инструментом выделения, чтобы переместить его. Нижний правый маркер изменяет размер. Двойной щелчок по тексту открывает ввод; Enter завершает ввод, Esc отменяет его. Пустой текст удаляет существующую надпись.
- Цвет, толщина, размер текста, полужирное начертание, заливка и сила эффекта доступны в нижней строке панели для соответствующего инструмента.
- `⌘Z` отменяет, `⌘⇧Z` повторяет, Delete удаляет выделенный объект.
- Прокрутка сдвигает холст; `⌥` + прокрутка или жест сведения/разведения меняет масштаб. Пробел + перетаскивание также сдвигает холст.
- `Esc` закрывает захват/редактор без записи в историю. При активном текстовом поле сохраняются обычные сочетания для работы с текстом.
- PNG сохраняет исходное разрешение и прозрачность. JPEG выбирается в диалоге сохранения и использует белую подложку для прозрачных областей.

### OCR, закрепление и история

OCR обрабатывает итоговое изображение после обрезки и применения пометок/масок через системный Vision. Русский и английский распознаются локально при наличии поддержки в macOS. Копирование текста не закрывает редактор. Закрепление завершает редактирование и открывает готовое изображение поверх других окон; закреплённые окна можно перемещать, масштабировать, копировать и закрывать.

В историю попадают только завершённые снимки после копирования, сохранения или закрепления. Хранятся готовый PNG, его миниатюра и индекс; исходный кадр и объекты редактирования на диск не записываются. В истории можно добавить новые пометки поверх готовой картинки; старый блюр, текст и фигуры уже нельзя убрать. По умолчанию хранятся 100 снимков, лимит меняется в настройках. Данные находятся в `~/Library/Application Support/SnapMark`.

Язык: системный, русский или английский. Тема: системная, светлая или тёмная. Сочетание захвата переназначается в настройках. Если зарегистрировать новое сочетание не удалось, сохраняется предыдущее; зарезервированные системой сочетания могут перехватываться самой macOS.

Первая версия не содержит сети, аккаунтов, облака, записи видео и длинных снимков с прокруткой. Область захвата ограничена одним дисплеем; окно снимается как отдельное окно, без перекрывающих его приложений. Незавершённые сеансы и закрепления не восстанавливаются после перезапуска. Сборка подписана локально для личного использования, без Developer ID / нотариализации.

### Сборка и проверки

Нужны macOS 14+, Apple Silicon, Swift 6.2+ и Command Line Tools (`xcode-select --install`) либо Xcode. Зависимостей из сети нет.

```sh
./scripts/test.sh
./scripts/build-app.sh /absolute/path/to/output
```

`test.sh` запускает проверки модели/геометрии/рендера/реального файлового хранилища, затем нативные проверки жизненного цикла окон и настоящий Vision OCR. Для нативной части требуется графическая сессия macOS; окна проверки могут кратковременно появляться. Используется автономный Swift-раннер, поскольку поставка Command Line Tools может не содержать XCTest/Swift Testing. Любая проваленная проверка возвращает ненулевой код.

Пакет собирается через Swift Package Manager; `build-app.sh` создаёт и проверяет локальную подпись `.app`, создаёт иконку и ZIP. Для разработки можно открыть `Package.swift` в Xcode. `SnapMarkCore` содержит модель, рендерер и историю; `SnapMark` — захват, холст, интерфейс и системные интеграции. Контрольные сценарии и результаты этой сборки перечислены в `QA.md`.
