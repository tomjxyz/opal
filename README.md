# Opal

An AI assistant for BlackBerry 10, designed for the BlackBerry Classic. Ask a question by typing, or
point the camera at something and ask about it.

## Features

- **Ask anything.** Answers stream in and render as formatted text: headings, lists, tables, code
  and links.
- **Camera search.** Take a photo (or pick one from the gallery), add a question if you like, and
  ask. Tap the viewfinder to focus; the flash can be armed for one shot.
- **Translate.** In translate mode, a photo of text goes straight to a translation.
- **Web search (optional).** With a [Tavily](https://tavily.com) key, the model can search the web
  when a question needs current facts. Answers then list their sources.
- **Chats.** Conversations are saved on the device. Follow up, edit and re-ask a question, copy an
  answer, or export a chat as Markdown to `Documents/Opal`.
- **Any OpenAI-compatible server.** Works with OpenCode Go by default. Pick any model that accepts
  photos; prices are shown when the server lists them. "Quick answers" asks for minimal reasoning.
- **Keyboard and trackpad.** Full navigation with the Classic's trackpad and keyboard shortcuts.

Your API keys and chats stay on the phone. Requests go only to the server you configure and, if
web search is on, to Tavily.

## Install

Download `Opal.bar` from the latest release and sideload it. It's unsigned, so the device must
accept unsigned packages. `Opal-sim.bar` is for the BB10 Simulator.

Then open Settings and paste your API key.

## Building

```bash
docker run --rm -v "$PWD:/work" \
    ghcr.io/tomjxyz/bb10-sdk:10.3.1@sha256:7ddca3c5d11927bae1ff3077046de247d62a975b8f30531e7555cf23f35f34de \
    make both                                      # -> Opal.bar, Opal-sim.bar
```

The `bb10-sdk` image holds the BlackBerry Native SDK 10.3.1, GCC 5.4 cross compilers built from
source, and the shared build rules. The same digest is pinned in
`.github/workflows/release.yml`; use the one from the release tag you are checking. The UI images in `assets/` are generated from `art/` by
`tools/make-assets.py`.

## Verifying a release

Releases are built by GitHub Actions from the tagged commit, never on a personal machine. The build
is reproducible: the same commit and image always produce byte-identical files. Each release is
also covered by a signed build attestation. You can check a download in either of two ways.

**Rebuild it yourself.** This trusts nobody: it rebuilds the tag and compares every file in the
package with the one you downloaded.

```bash
docker run --rm -v "$PWD:/work" \
    ghcr.io/tomjxyz/bb10-sdk:10.3.1@sha256:7ddca3c5d11927bae1ff3077046de247d62a975b8f30531e7555cf23f35f34de \
    verify-bar.sh /work/Opal.bar https://github.com/tomjxyz/opal v1.0.0
```

`PASS` means the binary, QML, images and descriptor are exactly what that source produces. The
zip container (which stores timestamps) and the asset index's ordering are the only things not
compared byte for byte.

**Check the attestation.** This one trusts GitHub, which signs a statement (via Sigstore) that the
file was built by this repository's release workflow, and records from which commit.

```bash
gh attestation verify Opal.bar --repo tomjxyz/opal
```

Every release also includes `SHA256SUMS`.
