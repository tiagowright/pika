# Third-party notices

Pika itself is MIT licensed — see [LICENSE](LICENSE). It bundles or derives
from the following, whose notices are reproduced as their licences require.

---

## JetBrains Mono

Bundled as `Sources/Pika/Resources/JetBrainsMono.ttf` and copied into every
`Pika.app` build, so the licence ships in the app bundle as well as here.

- Upstream: <https://github.com/JetBrains/JetBrainsMono>
- Licence: SIL Open Font License 1.1
- Full text: [`Sources/Pika/Resources/JetBrainsMono-OFL.txt`](Sources/Pika/Resources/JetBrainsMono-OFL.txt)

> Copyright 2020 The JetBrains Mono Project Authors
> (https://github.com/JetBrains/JetBrainsMono)

The OFL reserves the font's name: the bundled copy is unmodified, and a
modified version would have to be renamed.

---

## Catppuccin (Mocha palette)

The colour values in `Sources/Pika/UI/Theme.swift` are the Catppuccin Mocha
palette, verified against the upstream palette definition.

- Upstream: <https://github.com/catppuccin/catppuccin>
- Licence: MIT

> MIT License
>
> Copyright (c) 2021 Catppuccin
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

---

## Pika's icon

`AppIcon.svg` (and the `AppIcon.icns` generated from it by `make_icon.sh`) is
an original design by Tiago Wright, drawn by hand in the Catppuccin Mocha
palette. It carries the same MIT licence as the rest of the project.
