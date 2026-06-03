# E2E

[中文](README.md) | **English**

E2E is a small macOS reading assistant. The idea is **English Explain English**: instead of translating English into another language, it explains a word or phrase in simple English based on the context you are reading.

You select a sentence or short passage first, then select the word you do not understand inside E2E. The app explains the meaning that fits that exact context.

![E2E usage preview](docs/assets/e2e-preview.png)

## Download

Most users should download the ready-to-run app:

1. Open the latest release: <https://github.com/zhonghaoyi/E2E/releases/latest>
2. Download `E2E-macOS-0.1.1.zip`
3. Unzip it
4. Move `E2E.app` to your `Applications` folder
5. Open `E2E.app`

This open-source build is not notarized by Apple yet. On first launch, macOS may say the developer cannot be verified. If that happens:

1. Right-click `E2E.app`
2. Choose `Open`
3. Click `Open` again

If the dialog only shows `Done` and `Move to Bin`:

1. Click `Done`
2. Open `System Settings`
3. Go to `Privacy & Security`
4. Scroll to `Security`
5. Find the message saying `E2E` was blocked
6. Click `Open Anyway`

If you are comfortable with Terminal, you can also run:

```bash
xattr -dr com.apple.quarantine /Applications/E2E.app
```

After the first launch, it should open normally.

## Requirements

- macOS 14 or later
- An OpenRouter API key or an OpenAI API key

Each user enters their own API key. E2E does not include a built-in key.

## First Setup

1. Open E2E.
2. Click `Settings`.
3. Choose `OpenRouter` or `OpenAI`.
4. Paste your API key.
5. Click `Refresh` to load models.
6. Choose a model.
7. Click `Test`.
8. Click `Save`.

Your API key is stored in macOS Keychain. It is not written to the app bundle, GitHub repository, or history file.

## How To Use

1. In a paper, webpage, PDF, email, or another app, select the full sentence or short passage.
2. Press `Command+C` twice.
3. E2E brings the text into the `Context` box.
4. Inside the `Context` box, select the exact word or phrase you want explained.
5. Click `Explain`.

E2E shows:

- Meaning in this context
- Simple replacement
- Easy example
- Part of speech
- History occurrence count

## History

By default, history is saved here:

```text
~/Library/Application Support/E2E/history.json
```

You can choose a custom history path in Settings, including a cloud-drive folder. History is a local JSON file and is not uploaded by the app.

## Story

The `Story` tab chooses words from your history and generates a short, simple English passage for practice.

You can filter words by:

- Time range: 1 day, 1 week, 1 month, 3 months
- Occurrence count: all, 1 time, more than 3, more than 7
- Word limit: 10, 30, 50, 70, 100

History words are highlighted in the generated story. Clicking a highlighted word opens the matching history record. A Chinese translation button is available for checking your understanding.

## Privacy

E2E is local-first:

- API keys are stored in macOS Keychain.
- Settings are stored in macOS UserDefaults.
- History is stored in a local JSON file.
- Selected text is sent to your chosen LLM provider only when you ask E2E to explain or generate a story.
- The app does not include any built-in API key.

## Developers

To build or modify the app yourself, see the [developer build guide](docs/install-from-source.en.md).

## License

MIT License. See [LICENSE](LICENSE).
