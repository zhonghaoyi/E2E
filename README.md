# E2E

E2E is a small macOS reading assistant for people who want English explained in English.

It is not a normal translation app. You select a sentence or paragraph, then select the word or phrase you do not understand inside E2E. The app explains that word in simple English, based on the context you gave it.

![E2E app icon](Resources/AppIcon.png)

## What It Does

- Explains selected English words or phrases in simple English.
- Uses the surrounding context you select, so the meaning matches the sentence.
- Supports OpenRouter and OpenAI-compatible chat APIs.
- Lets each user enter their own API key.
- Stores API keys in macOS Keychain, not in project files.
- Saves local history so you can review words later.
- Groups history by time range and occurrence count.
- Generates short practice stories from your history words.
- Lets you translate generated stories into Chinese for checking.
- Supports `Command+C` twice as the main capture shortcut.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools.
- An OpenRouter API key or an OpenAI API key.

Install Xcode Command Line Tools if you do not have them:

```bash
xcode-select --install
```

## Install From Source

Clone the repository:

```bash
git clone https://github.com/zhonghaoyi/E2E.git
cd E2E
```

Build the app:

```bash
./build.sh
```

The built app will appear here:

```text
.build/ContextualExplainer.app
```

For normal use, copy it to Applications:

```bash
cp -R .build/ContextualExplainer.app /Applications/ContextualExplainer.app
```

Then open it from Applications.

Because this is an open-source build and may not be notarized, macOS may show a security warning the first time you open it. If that happens, right-click the app and choose `Open`.

## First Setup

1. Open the app.
2. Click `Settings`.
3. Choose `OpenRouter` or `OpenAI`.
4. Paste your API key.
5. Click `Refresh` to load available models.
6. Choose a model.
7. Click `Test`.
8. Click `Save`.

Your API key is saved in macOS Keychain. It is not written to the repository, the app bundle, or `history.json`.

## How To Use

1. In another app, select the full sentence or paragraph you are reading.
2. Press `Command+C` twice.
3. E2E brings that text into the `Context` box.
4. Inside the `Context` box, select the exact word or phrase you want explained.
5. Click `Explain`.

The app will show:

- Meaning
- Simple replacement
- Easy example
- Part of speech
- History occurrence count

## History

By default, history is saved here:

```text
~/Library/Application Support/ContextualExplainer/history.json
```

You can choose a custom history path in Settings. For example, you can save `history.json` in a cloud drive folder if you want to sync it yourself.

History records are local files. They are not uploaded by the app.

## Practice Story

The `Story` tab can choose words from your history and ask the model to write a short, simple story.

You can filter the word pool by:

- Time range: 1 day, 1 week, 1 month, 3 months
- Occurrence count: all, 1 time, more than 3, more than 7
- Word count limit: 10, 30, 50, 70, 100

Words from your history are highlighted in the generated story. Clicking a highlighted word opens the matching history entry.

## Privacy

E2E is designed to be local-first:

- API keys are stored in macOS Keychain.
- Settings are stored in macOS UserDefaults.
- History is stored in a local JSON file.
- The app sends the selected context and target word to your chosen LLM provider when you click `Explain`.
- The app does not include any built-in API key.

Before publishing or sharing your own fork, do not commit:

- `.build/`
- `.env`
- `history.json`
- local screenshots with private content
- API keys or provider tokens

## Build Notes

This project intentionally uses a small shell build script instead of a full Xcode project:

```bash
./build.sh
```

The script compiles the Swift files, copies `Resources/Info.plist` and `Resources/AppIcon.icns`, then signs the local app with an ad-hoc signature.

## Troubleshooting

If `Command+C` twice does not work, make sure you are selecting the full context text first, then copying twice quickly.

If direct selection capture or `Command+Shift+E` does not work, enable Accessibility permission:

```text
System Settings -> Privacy & Security -> Accessibility
```

If macOS still shows old permission state after enabling it, restart the app.

If the Dock still shows an old icon after rebuilding, macOS is probably using its icon cache. The app bundle can still contain the new icon.

## License

MIT License. See [LICENSE](LICENSE).
